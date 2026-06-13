//go:build !windows

package mpv

import (
	"fmt"
	"net"
	"os"
	"path/filepath"
)

func getSocketPath() string {
	return filepath.Join(os.TempDir(), "anistream_mpv.sock")
}

// GetIpcArg returns the MPV argument for creating the IPC socket.
func GetIpcArg() string {
	return fmt.Sprintf("--input-ipc-server=%s", getSocketPath())
}

// CleanupIpc removes any dead socket files left over from crashes.
func CleanupIpc() {
	_ = os.Remove(getSocketPath())
}

// DialMpv connects to the running MPV instance via Unix socket.
func DialMpv() (net.Conn, error) {
	return net.Dial("unix", getSocketPath())
}
