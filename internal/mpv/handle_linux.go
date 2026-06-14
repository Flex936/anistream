//go:build linux

package mpv

import (
	"fmt"
	"log"
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

// applyLinuxZOrderFix polls for MPV's X11 child window under parentXID and
// lowers it in the stacking order so the WebKit2GTK surface sits on top.
// This makes the Svelte glass UI visible over the native video layer.
func applyLinuxZOrderFix(parentXID uintptr) {
	// Poll for up to 5 s for MPV to create its child window.
	deadline := time.Now().Add(5 * time.Second)
	parentHex := fmt.Sprintf("0x%x", parentXID)

	for time.Now().Before(deadline) {
		// xdotool search returns child window IDs of the given parent.
		out, err := exec.Command("xdotool", "search", "--onlyvisible", "--classname", "mpv").Output()
		if err == nil && len(strings.TrimSpace(string(out))) > 0 {
			lines := strings.Fields(strings.TrimSpace(string(out)))
			for _, wid := range lines {
				// Lower the MPV window so WebKit2GTK sits on top.
				if err2 := exec.Command("xdotool", "windowlower", wid).Run(); err2 == nil {
					log.Printf("[MPV Engine] Linux Z-Order fix applied (mpv wid=%s parent=%s).", wid, parentHex)
					return
				}
			}
		}

		// Fallback: query child windows of the parent XID directly via xwininfo.
		out2, err2 := exec.Command("xwininfo", "-id", parentHex, "-children").Output()
		if err2 == nil {
			for _, line := range strings.Split(string(out2), "\n") {
				line = strings.TrimSpace(line)
				if !strings.HasPrefix(line, "0x") {
					continue
				}
				fields := strings.Fields(line)
				if len(fields) == 0 {
					continue
				}
				child := fields[0]
				parsed, perr := strconv.ParseUint(strings.TrimPrefix(child, "0x"), 16, 64)
				if perr != nil {
					continue
				}
				child = fmt.Sprintf("%d", parsed)
				if err3 := exec.Command("xdotool", "windowlower", child).Run(); err3 == nil {
					log.Printf("[MPV Engine] Linux Z-Order fix applied via xwininfo (child=%s parent=%s).", child, parentHex)
					return
				}
			}
		}

		time.Sleep(200 * time.Millisecond)
	}
	log.Println("[MPV Engine] Linux Z-Order fix: timed out waiting for MPV child window.")
}
