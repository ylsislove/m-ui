package main

import (
	"context"
	"net"
	"testing"
	"time"
)

func TestParseScreenState(t *testing.T) {
	tests := []struct {
		name   string
		input  string
		wanted string
	}{
		{"on", "Display Power: state=ON\n  mScreenState=ON\n", "ON"},
		{"off", "  mScreenState=OFF\n", "OFF"},
		{"missing", "Display Power: unknown\n", ""},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if got := parseScreenState(test.input); got != test.wanted {
				t.Fatalf("parseScreenState() = %q, want %q", got, test.wanted)
			}
		})
	}
}

func TestParseWakefulness(t *testing.T) {
	tests := []struct {
		input  string
		wanted string
	}{
		{"mWakefulness=Awake", "ON"},
		{"mWakefulness=Asleep", "OFF"},
		{"mWakefulness=Dozing", "OFF"},
		{"mWakefulness=Unknown", ""},
	}

	for _, test := range tests {
		if got := parseWakefulness(test.input); got != test.wanted {
			t.Fatalf("parseWakefulness(%q) = %q, want %q", test.input, got, test.wanted)
		}
	}
}

func TestChecksum(t *testing.T) {
	if got := checksum([]byte{1, 2, 3, 255}); got != 261 {
		t.Fatalf("checksum() = %d, want 261", got)
	}
}

func TestProbeTCP(t *testing.T) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()

	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	if err := probeTCP(ctx, listener.Addr().String()); err != nil {
		t.Fatalf("probeTCP() returned %v", err)
	}
}
