//go:build windows

package mpv

import (
	"fmt"
	"net"
	"time"

	"gopkg.in/natefinch/npipe.v2"
)

const pipeName = `\\.\pipe\anistream_mpv_ipc`

// GetIpcArg returns the MPV argument for creating the IPC socket.
func GetIpcArg() string {
	return fmt.Sprintf("--input-ipc-server=%s", pipeName)
}

// CleanupIpc is a no-op on Windows; named pipes clean up automatically.
func CleanupIpc() {}

// DialMpv connects to the running MPV instance via Windows Named Pipe.
func DialMpv() (net.Conn, error) {
	return npipe.DialTimeout(pipeName, 2*time.Second)
}
