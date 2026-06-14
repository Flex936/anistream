//go:build darwin

package mpv

// handle_darwin.go — native view embedding for macOS via Cocoa/Objective-C.
//
// On macOS, MPV's --wid flag expects an NSView pointer.  We cannot simply pass
// the NSWindow's contentView because WKWebView is already a subview of it —
// giving the same NSView to MPV would cause rendering conflicts.
//
// Solution: create a new NSView, insert it at index 0 of the contentView's
// subview array (which in Cocoa's back-to-front ordering means "furthest back"),
// and pass THAT pointer to MPV.  WKWebView remains on top; MPV renders into the
// dedicated view below it.
//
// AcquireWindowHandle returns a non-zero sentinel (1) to signal that the
// platform is ready.  The real per-session NSView is created inside
// PrepareVideoSurface so that each Play() call gets a fresh view.
//
// Build requirement: Xcode Command Line Tools (ships Cocoa headers).
//   xcode-select --install

/*
#cgo CFLAGS: -x objective-c
#cgo LDFLAGS: -framework Cocoa

#import <Cocoa/Cocoa.h>

// createMPVSubview allocates a new NSView of size (w × h), inserts it at the
// *bottom* of the contentView's subview stack (index 0, behind WKWebView), and
// returns its pointer as a uintptr_t for MPV's --wid argument.
//
// Autoresizing mask: the subview stretches with the window so it always fills
// the frame even after the user resizes the AniStream window.
uintptr_t createMPVSubview(int w, int h) {
    // Prefer the key window (focused) then fall back to mainWindow.
    NSWindow* win = [[NSApplication sharedApplication] keyWindow];
    if (!win) win = [[NSApplication sharedApplication] mainWindow];
    if (!win) return 0;

    NSView* contentView = [win contentView];
    NSRect frame = NSMakeRect(0, 0, (CGFloat)w, (CGFloat)h);

    NSView* mpvView = [[NSView alloc] initWithFrame:frame];
    // Stretch with the window in both axes.
    [mpvView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

    // NSWindowBelow + relativeTo:nil  →  insert before all existing subviews,
    // i.e., at index 0, which is the furthest-back layer in Cocoa rendering.
    [contentView addSubview:mpvView
                 positioned:NSWindowBelow
                 relativeTo:nil];

    // Return the raw pointer; Go casts it to uintptr and formats it for --wid.
    return (uintptr_t)mpvView;
}
*/
import "C"
import "fmt"

// AcquireWindowHandle returns a sentinel (1) on macOS.
// The actual NSView is created per-Play in PrepareVideoSurface; there is no
// single "parent handle" to acquire at startup as there is on Windows/Linux.
func AcquireWindowHandle() (uintptr, error) {
	return 1, nil // sentinel: platform initialised, surface created later
}

// PrepareVideoSurface creates a dedicated NSView below WKWebView and returns
// its pointer for MPV's --wid flag.
func PrepareVideoSurface(_ uintptr, w, h int) (uintptr, error) {
	if w == 0 {
		w = 1280
	}
	if h == 0 {
		h = 720
	}

	view := uintptr(C.createMPVSubview(C.int(w), C.int(h)))
	if view == 0 {
		return 0, fmt.Errorf(
			"createMPVSubview returned nil — " +
				"NSApp has no key or main window yet; retry after the window becomes visible")
	}
	return view, nil
}

// applyLinuxZOrderFix is a no-op on macOS.
func applyLinuxZOrderFix(_ uintptr) {}
