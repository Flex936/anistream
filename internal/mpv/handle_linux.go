//go:build linux

package mpv

import (
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"time"
)

// AcquireWindowHandle returns the X11 Window XID for the Wails GTK window.
func AcquireWindowHandle() (uintptr, error) {
	var lastErr error

	// Retry loop: The X11 window takes a fraction of a second to be mapped and
	// become visible to the compositor after Wails calls startup().
	// We will poll for up to 2 seconds.
	for i := 0; i < 20; i++ {
		// 1. Try xdotool
		xid, err := getXidWithXdotool()
		if err == nil {
			return xid, nil
		}
		lastErr = err

		// 2. Try xprop fallback
		xid, err = getXidWithXprop()
		if err == nil {
			return xid, nil
		}

		time.Sleep(100 * time.Millisecond)
	}

	return 0, fmt.Errorf("timeout waiting for X11 window to become visible. Last xdotool err: %v", lastErr)
}

func getXidWithXdotool() (uintptr, error) {
	pid := strconv.Itoa(os.Getpid())
	out, err := exec.Command("xdotool", "search", "--pid", pid, "--onlyvisible").Output()
	if err != nil {
		return 0, err
	}

	lines := strings.Fields(strings.TrimSpace(string(out)))
	if len(lines) == 0 {
		return 0, fmt.Errorf("no visible windows found")
	}

	xid, err := strconv.ParseUint(lines[len(lines)-1], 10, 64)
	if err != nil {
		return 0, err
	}

	return uintptr(xid), nil
}

// getXidWithXprop manually queries the X server for all managed windows,
// then filters them by our exact Process ID.
func getXidWithXprop() (uintptr, error) {
	pid := os.Getpid()

	// Get all window IDs managed by the X Server
	out, err := exec.Command("xprop", "-root", "_NET_CLIENT_LIST").Output()
	if err != nil {
		return 0, err
	}

	parts := strings.Split(string(out), "#")
	if len(parts) < 2 {
		return 0, fmt.Errorf("could not parse X11 client list")
	}

	winIDs := strings.Split(parts[1], ",")
	for _, widStr := range winIDs {
		widStr = strings.TrimSpace(widStr)
		if widStr == "" {
			continue
		}

		// Check the PID owner of this specific window
		pidOut, err := exec.Command("xprop", "-id", widStr, "_NET_WM_PID").Output()
		if err != nil {
			continue
		}

		// If the window belongs to our Go application...
		if strings.Contains(string(pidOut), fmt.Sprintf("= %d", pid)) {
			// Convert the hex string (e.g., "0x2400006") to a uintptr
			parsed, err := strconv.ParseUint(strings.TrimPrefix(widStr, "0x"), 16, 64)
			if err == nil {
				return uintptr(parsed), nil
			}
		}
	}

	return 0, fmt.Errorf("no window matching our PID was found")
}

func PrepareVideoSurface(parent uintptr, _, _ int) (uintptr, error) {
	return parent, nil
}
