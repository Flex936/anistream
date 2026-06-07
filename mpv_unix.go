//go:build !windows

package main

import (
	"net"
	"os"
	"os/exec"
	"path/filepath"
)

func getSocketPath() string {
	return filepath.Join(os.TempDir(), "anistream-mpv.sock")
}

// GetIpcArg returns the mpv command line argument for Unix Domain Sockets
func GetIpcArg() string {
	return "--input-ipc-server=" + getSocketPath()
}

// CleanupIpc removes the stale unix socket if it was left behind by a crash
func CleanupIpc() {
	_ = os.Remove(getSocketPath())
}

// DialMpv connects to the MPV IPC server via standard net.Dial
func DialMpv() (net.Conn, error) {
	return net.Dial("unix", getSocketPath())
}

// KillProcess sends standard SIGKILL on Unix systems
func KillProcess(cmd *exec.Cmd) error {
	return cmd.Process.Kill()
}
