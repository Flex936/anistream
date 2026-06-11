//go:build !windows

package mpv

import (
	"net"
	"os"
	"os/exec"
	"path/filepath"
)

func getSocketPath() string {
	return filepath.Join(os.TempDir(), "anistream-mpv.sock")
}

// GetIpcArg returns the mpv flag for Unix domain sockets.
func GetIpcArg() string {
	return "--input-ipc-server=" + getSocketPath()
}

// CleanupIpc removes a stale socket left by a previous crash.
func CleanupIpc() {
	_ = os.Remove(getSocketPath())
}

// DialMpv connects to the running mpv IPC server.
func DialMpv() (net.Conn, error) {
	return net.Dial("unix", getSocketPath())
}

// killProcess sends SIGKILL to the process. Unexported — only Manager calls it.
func killProcess(cmd *exec.Cmd) error {
	return cmd.Process.Kill()
}
