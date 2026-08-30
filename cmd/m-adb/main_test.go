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

func TestResolveScreenState(t *testing.T) {
	tests := []struct {
		name        string
		display     string
		wakefulness string
		wanted      string
	}{
		{"awake and display on", "ON", "ON", "ON"},
		{"quiet boot false on", "ON", "OFF", "OFF"},
		{"display off wins", "OFF", "ON", "OFF"},
		{"display fallback", "ON", "", "ON"},
		{"wakefulness fallback", "", "OFF", "OFF"},
		{"both missing", "", "", ""},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if got := resolveScreenState(test.display, test.wakefulness); got != test.wanted {
				t.Fatalf("resolveScreenState(%q, %q) = %q, want %q", test.display, test.wakefulness, got, test.wanted)
			}
		})
	}
}

func TestParsePowerTime(t *testing.T) {
	output := "  mLastWakeTime=334405 (158697 ms ago)\n  mLastSleepTime=331628 (161474 ms ago)\n"
	if got, ok := parsePowerTime(output, "mLastWakeTime"); !ok || got != 334405 {
		t.Fatalf("parsePowerTime(last wake) = %d, %v; want 334405, true", got, ok)
	}
	if got, ok := parsePowerTime(output, "mLastSleepTime"); !ok || got != 331628 {
		t.Fatalf("parsePowerTime(last sleep) = %d, %v; want 331628, true", got, ok)
	}
	if _, ok := parsePowerTime(output, "mMissingTime"); ok {
		t.Fatal("parsePowerTime(missing) unexpectedly succeeded")
	}
}

func TestResolveObservedScreenState(t *testing.T) {
	displayOn := "  mScreenState=ON\n"
	tests := []struct {
		name   string
		power  string
		wanted string
	}{
		{
			name:   "system quiet reboot still asleep",
			power:  "mWakefulness=Asleep\n" + bootReasonMarker + "\nreboot,quiet\n",
			wanted: "OFF",
		},
		{
			name:   "adb quiet reboot before physical wake",
			power:  "mWakefulness=Awake\nmLastWakeTime=0 (25000 ms ago)\nmLastSleepTime=0 (25000 ms ago)\n" + bootReasonMarker + "\nreboot,quiet\n",
			wanted: "OFF",
		},
		{
			name:   "quiet reboot after remote wake",
			power:  "mWakefulness=Awake\nmLastWakeTime=334405 (100 ms ago)\nmLastSleepTime=331628 (2877 ms ago)\n" + bootReasonMarker + "\nreboot,quiet\n",
			wanted: "ON",
		},
		{
			name:   "normal boot keeps existing behavior",
			power:  "mWakefulness=Awake\nmLastWakeTime=0 (25000 ms ago)\nmLastSleepTime=0 (25000 ms ago)\n" + bootReasonMarker + "\nwarm\n",
			wanted: "ON",
		},
		{
			name:   "missing wake history does not guess",
			power:  "mWakefulness=Awake\n" + bootReasonMarker + "\nreboot,quiet\n",
			wanted: "ON",
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if got := resolveObservedScreenState(displayOn, test.power); got != test.wanted {
				t.Fatalf("resolveObservedScreenState() = %q, want %q", got, test.wanted)
			}
		})
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
