//go:build windows

package mpv

// handle_windows.go — native window handle acquisition for Windows.
//
// AcquireWindowHandle: scans all top-level windows via EnumWindows to find the
// HWND belonging to this process. No CGo required — all calls go through the
// standard syscall lazy-DLL loader.
//
// PrepareVideoSurface: creates a "STATIC" child HWND at HWND_BOTTOM so that
// the WebView2 sibling window (created earlier by Wails) remains on top.
// MPV's --wid embeds its rendering surface inside this child HWND.
//
// WndProc subclass (resize + focus restoration)
// ─────────────────────────────────────────────
// We subclass the parent HWND to intercept two message types:
//
//   WM_SIZE — keep the MPV STATIC surface sized to the parent client area.
//     Without this, alt-tab / maximise / fullscreen leave the surface at its
//     original size while WebView2 resizes correctly, causing visual corruption.
//
//   WM_ACTIVATE — restore WebView2 keyboard/mouse focus after alt-tab.
//     When the top-level window is re-activated Windows sends WM_ACTIVATE, but
//     WebView2 (a child window) does not automatically re-acquire input focus.
//     We explicitly find the WebView2 child (class "Chrome_WidgetWin_*") and
//     call SetFocus on it.  This fixes the "video plays but window is frozen"
//     symptom after every alt-tab.
//
// Z-order rationale
// ─────────────────
// Wails creates the parent HWND, then WebView2 creates its child window.
// When MPV later calls --wid, it creates ANOTHER child window — siblings ordered
// later in creation time are "on top" by default.  By having MPV embed into a
// pre-created child that we've explicitly placed at HWND_BOTTOM, WebView2 always
// wins the z-order without any post-hoc window manipulation.

import (
	"fmt"
	"log"
	"os"
	"sync/atomic"
	"syscall"
	"time"
	"unsafe"
)

var (
	user32                 = syscall.NewLazyDLL("user32.dll")
	procEnumWindows        = user32.NewProc("EnumWindows")
	procGetWindowThreadPID = user32.NewProc("GetWindowThreadProcessId")
	procIsWindowVisible    = user32.NewProc("IsWindowVisible")
	procGetParent          = user32.NewProc("GetParent")
	procCreateWindowExW    = user32.NewProc("CreateWindowExW")
	procSetWindowPos       = user32.NewProc("SetWindowPos")
	procGetClientRect      = user32.NewProc("GetClientRect")
	procSetWindowLongPtrW  = user32.NewProc("SetWindowLongPtrW")
	procCallWindowProcW    = user32.NewProc("CallWindowProcW")
	procGetWindow          = user32.NewProc("GetWindow")
	procGetClassNameW      = user32.NewProc("GetClassNameW")
	procSetFocus           = user32.NewProc("SetFocus")
)

// Win32 constants — declare locally so we don't need an external package.
const (
	wsChild       uintptr = 0x40000000
	wsVisible     uintptr = 0x10000000
	swpNoActivate uintptr = 0x0010
	swpNoZOrder   uintptr = 0x0004
	hwndBottom    uintptr = 1

	gwlpWndproc uintptr = ^uintptr(3) // GWLP_WNDPROC = -4 (two's complement, platform-width)

	wmSize     uintptr = 0x0005
	wmActivate uintptr = 0x0006
	waInactive uintptr = 0 // low word of WM_ACTIVATE wParam when deactivating

	gwChild    uintptr = 5 // GetWindow: first child
	gwHwndNext uintptr = 2 // GetWindow: next sibling
)

// winRECT mirrors the Win32 RECT structure used by GetClientRect.
type winRECT struct {
	Left, Top, Right, Bottom int32
}

// activeSurface is the child HWND that MPV renders into.
// Written once in PrepareVideoSurface, read in the WndProc subclass hook.
var activeSurface atomic.Uintptr

// origWndProc is the original WndProc of the parent window saved by
// SetWindowLongPtrW so we can chain it from our subclass procedure.
var origWndProc atomic.Uintptr

// findWebView2Child walks the window tree rooted at parent (depth-first) and
// returns the first child whose class name begins with "Chrome_WidgetWin".
// That window is the WebView2 renderer host that needs explicit focus after
// an alt-tab re-activation.
//
// We avoid EnumChildWindows (which requires a Go callback, consuming one of
// the 1024 global slots) and instead walk with GetWindow so we never allocate
// a callback slot in this hot path.
func findWebView2Child(parent uintptr) uintptr {
	child, _, _ := procGetWindow.Call(parent, gwChild)
	for child != 0 {
		var buf [128]uint16
		n, _, _ := procGetClassNameW.Call(child, uintptr(unsafe.Pointer(&buf[0])), uintptr(len(buf)))
		if n >= 16 { // "Chrome_WidgetWin" is 16 chars
			// Compare the first 16 UTF-16 code units without converting to string.
			match := buf[0] == 'C' && buf[1] == 'h' && buf[2] == 'r' && buf[3] == 'o' &&
				buf[4] == 'm' && buf[5] == 'e' && buf[6] == '_' && buf[7] == 'W' &&
				buf[8] == 'i' && buf[9] == 'd' && buf[10] == 'g' && buf[11] == 'e' &&
				buf[12] == 't' && buf[13] == 'W' && buf[14] == 'i' && buf[15] == 'n'
			if match {
				return child
			}
		}
		// Recurse into this child's subtree before moving to the next sibling.
		if grand := findWebView2Child(child); grand != 0 {
			return grand
		}
		child, _, _ = procGetWindow.Call(child, gwHwndNext)
	}
	return 0
}

// subclassWndProc is the replacement WndProc we install on the parent HWND.
//
//	WM_SIZE   → resize the MPV surface child to the new client dimensions.
//	WM_ACTIVATE (activation) → forward to original, then restore WebView2 focus.
//	everything else → forward to the original WndProc unchanged.
var subclassWndProc = syscall.NewCallback(func(hwnd, msg, wParam, lParam uintptr) uintptr {
	orig := origWndProc.Load()
	if orig == 0 {
		// origWndProc not yet committed — this is a TOCTOU window between
		// SetWindowLongPtrW installing the subclass and Store() writing the
		// previous procedure address.  Return 0 (safe no-op) rather than
		// calling CallWindowProc(NULL,...) which is undefined behaviour.
		return 0
	}

	switch msg {
	case wmSize:
		// Resize the MPV surface to match the new client area.
		// lParam low word = new width, high word = new height.
		w := lParam & 0xFFFF
		h := (lParam >> 16) & 0xFFFF
		if surf := activeSurface.Load(); surf != 0 && w > 0 && h > 0 {
			procSetWindowPos.Call(
				surf,
				0, // hWndInsertAfter (ignored — SWP_NOZORDER)
				0, 0, w, h,
				swpNoActivate|swpNoZOrder,
			)
		}

	case wmActivate:
		// Forward the message first so Wails' own handler runs (it may update
		// ICoreWebView2Controller visibility state, etc.).
		ret, _, _ := procCallWindowProcW.Call(orig, hwnd, msg, wParam, lParam)

		// After activation (not deactivation), explicitly restore WebView2
		// keyboard/mouse focus.  Wails/WebView2 does not do this automatically,
		// producing the "video plays but window is frozen after alt-tab" bug.
		waCode := wParam & 0xFFFF
		if waCode != waInactive {
			if wv2 := findWebView2Child(hwnd); wv2 != 0 {
				procSetFocus.Call(wv2)
			} else {
				// Fallback: focus the parent and let DefWindowProc route to
				// the last-focused child.
				procSetFocus.Call(hwnd)
			}
		}
		return ret
	}

	// Default: forward everything else to the original WndProc.
	ret, _, _ := procCallWindowProcW.Call(orig, hwnd, msg, wParam, lParam)
	return ret
})

// installSubclass replaces the parent HWND's WndProc with subclassWndProc
// and saves the original so we can chain it.  Safe to call multiple times
// (subsequent calls are no-ops because origWndProc is already non-zero).
//
// SetWindowLongPtrW may be called from any thread within the same process —
// Windows does not restrict cross-thread subclassing within a single process.
// The replacement WndProc is always dispatched on the message-pump thread
// (the thread that owns the HWND), regardless of which thread set it.
func installSubclass(parent uintptr) {
	if origWndProc.Load() != 0 {
		return // already installed
	}
	prev, _, err := procSetWindowLongPtrW.Call(parent, gwlpWndproc, subclassWndProc)
	if prev != 0 {
		origWndProc.Store(prev)
		log.Printf("[MPV] WndProc subclass installed on HWND 0x%x (WM_SIZE + WM_ACTIVATE)", parent)
	} else {
		// A zero return value means the call failed.  Without the subclass
		// neither WM_SIZE (resize) nor WM_ACTIVATE (focus) will be handled,
		// so log loudly rather than silently continuing.
		log.Printf("[MPV] WARNING: SetWindowLongPtrW failed on HWND 0x%x: %v — alt-tab freeze and resize bugs will persist", parent, err)
	}
}

// AcquireWindowHandle returns the top-level HWND belonging to this process.
// It retries for up to 2 s to handle the race between startup() and Wails
// making the window visible (especially slow in `wails dev` / WebView2 init).
func AcquireWindowHandle() (uintptr, error) {
	pid := uint32(os.Getpid())

	var found uintptr
	cb := syscall.NewCallback(func(hwnd, _ uintptr) uintptr {
		// Filter by PID.
		var procID uint32
		procGetWindowThreadPID.Call(hwnd, uintptr(unsafe.Pointer(&procID)))
		if procID != pid {
			return 1 // continue
		}
		// Only top-level windows (no parent).
		parent, _, _ := procGetParent.Call(hwnd)
		if parent != 0 {
			return 1
		}
		// Must be visible — Wails' frameless window is always visible once ready.
		// In dev mode WebView2 initialisation can delay visibility by ~500 ms.
		vis, _, _ := procIsWindowVisible.Call(hwnd)
		if vis == 0 {
			return 1
		}
		found = hwnd
		return 0 // stop enumeration
	})

	// Retry loop: give Wails up to 2 s to show the window.
	const (
		maxAttempts = 20
		retryDelay  = 100 * time.Millisecond
	)
	for i := range maxAttempts {
		found = 0
		procEnumWindows.Call(cb, 0)
		if found != 0 {
			return found, nil
		}
		if i < maxAttempts-1 {
			time.Sleep(retryDelay)
		}
	}
	return 0, fmt.Errorf("EnumWindows: no visible top-level HWND found for PID %d after %v",
		pid, time.Duration(maxAttempts)*retryDelay)
}

// PrepareVideoSurface creates a child "STATIC" HWND inside parent and places it
// at HWND_BOTTOM so WebView2 (created earlier) remains the topmost sibling.
// MPV receives this child HWND via --wid and renders its video inside it.
//
// It also installs a WndProc subclass on the parent so that:
//   - WM_SIZE → the MPV surface is always resized to match the parent client area
//   - WM_ACTIVATE → WebView2 keyboard/mouse focus is restored after alt-tab
func PrepareVideoSurface(parent uintptr, w, h int) (uintptr, error) {
	// If caller passed zero dimensions, read them from the parent client area.
	if w == 0 || h == 0 {
		var rect winRECT
		procGetClientRect.Call(parent, uintptr(unsafe.Pointer(&rect)))
		w = int(rect.Right - rect.Left)
		h = int(rect.Bottom - rect.Top)
	}

	// "STATIC" is a built-in Win32 window class — no RegisterClassEx needed.
	cls, _ := syscall.UTF16PtrFromString("STATIC")

	hwnd, _, err := procCreateWindowExW.Call(
		0,                            // dwExStyle
		uintptr(unsafe.Pointer(cls)), // lpClassName = "STATIC"
		0,                            // lpWindowName (null — no title)
		wsChild|wsVisible,            // dwStyle
		0, 0,                         // x, y
		uintptr(w), uintptr(h), // nWidth, nHeight
		parent,  // hWndParent
		0, 0, 0, // hMenu, hInstance, lpParam
	)
	if hwnd == 0 {
		return 0, fmt.Errorf("CreateWindowExW failed: %w", err)
	}

	// Push the new child to the absolute bottom of the sibling z-order.
	// SWP_NOACTIVATE: don't steal focus from the parent.
	procSetWindowPos.Call(
		hwnd,
		hwndBottom,
		0, 0, uintptr(w), uintptr(h),
		swpNoActivate,
	)

	// Publish the surface so the WndProc subclass can resize it on WM_SIZE.
	activeSurface.Store(hwnd)

	// Install the subclass hook for WM_SIZE (resize) and WM_ACTIVATE (focus).
	installSubclass(parent)

	return hwnd, nil
}
