package app

import (
	"testing"
	"time"

	"netease-music-mygo/internal/netease"
)

// A keychain that has the session only on a second read, as at a cold start
// while gnome-keyring still loads its keyrings, must still sign the app in:
// after a reboot it stayed signed out though the keychain had the session,
// and only a relaunch found it.
func TestSessionRetriedWhenTheKeychainIsLate(t *testing.T) {
	restore, account, waits := restoreLogin, accountProfile, sessionWaits
	defer func() { restoreLogin, accountProfile, sessionWaits = restore, account, waits }()
	sessionWaits = []time.Duration{0, 0}
	reads := 0
	restoreLogin = func() bool {
		reads++
		return reads > 1
	}
	accountProfile = func() (*netease.Profile, error) {
		return &netease.Profile{UserID: 7, Nickname: "小明"}, nil
	}

	prof, ok := waitForSession()
	if !ok || prof == nil || prof.UserID != 7 || reads != 2 {
		t.Fatalf("waitForSession() = %v, %v after %d read(s); want the profile from the second", prof, ok, reads)
	}
}
