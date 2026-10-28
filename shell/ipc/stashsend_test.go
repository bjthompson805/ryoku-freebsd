package main

import "testing"

// stashSendPath must preserve paths with spaces intact (a whitespace-split
// reimplementation would truncate "My File.deb" to "My"); empty means no file.
func TestStashSendPath(t *testing.T) {
	cases := []struct {
		line, want string
		ok         bool
	}{
		{"stash-send /home/u/app.deb", "/home/u/app.deb", true},
		{"stash-send /home/u/My File.deb", "/home/u/My File.deb", true},
		{"stash-send   /home/u/a b.deb", "/home/u/a b.deb", true},
		{"stash-send /home/u/a b.deb\n", "/home/u/a b.deb", true},
		{"stash-send", "", false},
		{"stash-send   ", "", false},
	}
	for _, c := range cases {
		got, ok := stashSendPath(c.line)
		if got != c.want || ok != c.ok {
			t.Fatalf("stashSendPath(%q) = (%q, %v), want (%q, %v)", c.line, got, ok, c.want, c.ok)
		}
	}
}
