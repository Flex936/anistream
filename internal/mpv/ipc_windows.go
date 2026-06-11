//go:build windows

package mpv

import (
	"net"
	"os/exec"
	"strconv"

	"gopkg.in/natefinch/npipe.v2"
)

// GetIpcArg returns the mpv flag for Windows named pipes.
func GetIpcArg() string {
	return `--input-ipc-server=\\.\pipe\mpv-pipe`
}

// CleanupIpc is a no-op on Windows; named pipes are self-cleaning.
func CleanupIpc() {}

// DialMpv connects to the running mpv IPC server via a named pipe.
func DialMpv() (net.Conn, error) {
	return npipe.Dial(`\\.\pipe\mpv-pipe`)
}

// killProcess terminates the entire process tree on Windows.
// taskkill /T is required because mpv may spawn FFmpeg child processes.
func killProcess(cmd *exec.Cmd) error {
	return exec.Command(
		"taskkill", "/F", "/T", "/PID", strconv.Itoa(cmd.Process.Pid),
	).Run()
}
