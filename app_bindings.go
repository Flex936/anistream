//go:build !torrent

package main

import "net/http"

func initTorrentEngine() error {
	return nil
}

func internalStreamTorrent(magnetLink string) (string, error) {
	return "", nil
}

func internalStreamHandler(w http.ResponseWriter, r *http.Request) {
}
