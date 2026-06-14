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
// Z-order rationale
// ─────────────────
// Wails creates the parent HWND, then WebView2 creates its child window.
// When MPV later calls --wid, it creates ANOTHER child window — siblings ordered
// later in creation time are "on top" by default.  By having MPV embed into a
// pre-created child that we've explicitly placed at HWND_BOTTOM, WebView2 always
// wins the z-order without any post-hoc window manipulation.

import (
	"fmt"
	"os"
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
)

// Win32 constants — declare locally so we don't need an external package.
const (
	wsChild         uintptr = 0x40000000
	wsVisible       uintptr = 0x10000000
	wsClipSiblings  uintptr = 0x04000000
	swpNoActivate   uintptr = 0x0010
	swpNoMove       uintptr = 0x0002
	swpNoSize       uintptr = 0x0001
	hwndBottom      uintptr = 1
)

// RECT mirrors the Win32 RECT structure used by GetClientRect.
type winRECT struct {
	Left, Top, Right, Bottom int32
}

// AcquireWindowHandle returns the top-level HWND belonging to this process.
// It is called once during startup() after Wails has made the window visible.
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
		// Must be visible — Wails' frameless window is always visible.
		vis, _, _ := procIsWindowVisible.Call(hwnd)
		if vis == 0 {
			return 1
		}
		found = hwnd
		return 0 // stop enumeration
	})

	procEnumWindows.Call(cb, 0)
	if found == 0 {
		return 0, fmt.Errorf("EnumWindows: no top-level HWND found for PID %d", pid)
	}
	return found, nil
}

// PrepareVideoSurface creates a child "STATIC" HWND inside parent and places it
// at HWND_BOTTOM so WebView2 (created earlier) remains the topmost sibling.
// MPV receives this child HWND via --wid and renders its video inside it.
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
		wsChild|wsVisible|wsClipSiblings, // dwStyle — WS_CLIPSIBLINGS prevents WebView2 from overpainting
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

	// Schedule a deferred re-enforcement: WebView2 may reorder siblings during
	// its own initialisation, so we push the MPV surface back down after a delay.
	go applyWindowsZOrderFix(hwnd, w, h)

	return hwnd, nil
}

// applyWindowsZOrderFix re-applies HWND_BOTTOM after a delay to counteract
// WebView2's sibling reordering during initialisation.
func applyWindowsZOrderFix(hwnd uintptr, w, h int) {
	for i := 0; i < 5; i++ {
		time.Sleep(300 * time.Millisecond)
		procSetWindowPos.Call(
			hwnd,
			hwndBottom,
			0, 0, uintptr(w), uintptr(h),
			swpNoActivate|swpNoMove|swpNoSize,
		)
	}
}

// applyLinuxZOrderFix is a no-op on Windows.
func applyLinuxZOrderFix(_ uintptr) {}

