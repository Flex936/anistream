//go:build windows

package main

import (
	"net"
	"os/exec"
	"strconv"

	"gopkg.in/natefinch/npipe.v2"
)

// GetIpcArg returns the mpv command line argument for Windows Named Pipes
func GetIpcArg() string {
	return "--input-ipc-server=\\\\.\\pipe\\mpv-pipe"
}

// CleanupIpc is a no-op on Windows, pipes clean themselves up
func CleanupIpc() {}

// DialMpv connects to the MPV IPC server via Windows Named Pipes
func DialMpv() (net.Conn, error) {
	return npipe.Dial(`\\.\pipe\mpv-pipe`)
}

// KillProcess forcefully terminates the process tree on Windows
func KillProcess(cmd *exec.Cmd) error {
	killCmd := exec.Command("taskkill", "/F", "/T", "/PID", strconv.Itoa(cmd.Process.Pid))
	return killCmd.Run()
}
