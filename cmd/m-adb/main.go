// m-adb implements the small subset of the legacy ADB-over-TCP protocol that
// m-ui needs. It intentionally has no external dependencies so it can be
// cross-compiled as a static binary for old OpenWrt/PandoraBox routers.
package main

import (
	"bytes"
	"context"
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"encoding/base64"
	"encoding/binary"
	"encoding/pem"
	"errors"
	"flag"
	"fmt"
	"io"
	"math/big"
	"net"
	"os"
	"path/filepath"
	"strings"
	"time"
)

const (
	programVersion = "1.2.1"
	adbVersion     = 0x01000000
	adbMaxPayload  = 4096
	maxReadPayload = 1024 * 1024

	aSync = 0x434e5953
	aCnxn = 0x4e584e43
	aOpen = 0x4e45504f
	aOkay = 0x59414b4f
	aClse = 0x45534c43
	aWrte = 0x45545257
	aAuth = 0x48545541

	authToken     = 1
	authSignature = 2
	authPublicKey = 3
)

type packet struct {
	command uint32
	arg0    uint32
	arg1    uint32
	payload []byte
}

type adbConn struct {
	net.Conn
}

func checksum(data []byte) uint32 {
	var sum uint32
	for _, value := range data {
		sum += uint32(value)
	}
	return sum
}

func (conn *adbConn) writePacket(command, arg0, arg1 uint32, payload []byte) error {
	header := make([]byte, 24)
	binary.LittleEndian.PutUint32(header[0:4], command)
	binary.LittleEndian.PutUint32(header[4:8], arg0)
	binary.LittleEndian.PutUint32(header[8:12], arg1)
	binary.LittleEndian.PutUint32(header[12:16], uint32(len(payload)))
	binary.LittleEndian.PutUint32(header[16:20], checksum(payload))
	binary.LittleEndian.PutUint32(header[20:24], command^0xffffffff)

	if _, err := conn.Write(header); err != nil {
		return err
	}
	if len(payload) > 0 {
		_, err := conn.Write(payload)
		return err
	}
	return nil
}

func (conn *adbConn) readPacket() (packet, error) {
	header := make([]byte, 24)
	if _, err := io.ReadFull(conn, header); err != nil {
		return packet{}, err
	}

	result := packet{
		command: binary.LittleEndian.Uint32(header[0:4]),
		arg0:    binary.LittleEndian.Uint32(header[4:8]),
		arg1:    binary.LittleEndian.Uint32(header[8:12]),
	}
	length := binary.LittleEndian.Uint32(header[12:16])
	wantChecksum := binary.LittleEndian.Uint32(header[16:20])
	magic := binary.LittleEndian.Uint32(header[20:24])

	if magic != result.command^0xffffffff {
		return packet{}, errors.New("ADB 数据包 magic 校验失败")
	}
	if length > maxReadPayload {
		return packet{}, fmt.Errorf("ADB 数据包过大：%d", length)
	}

	if length > 0 {
		result.payload = make([]byte, length)
		if _, err := io.ReadFull(conn, result.payload); err != nil {
			return packet{}, err
		}
		if wantChecksum != 0 && checksum(result.payload) != wantChecksum {
			return packet{}, errors.New("ADB 数据包 checksum 校验失败")
		}
	}
	return result, nil
}

func loadOrCreateKey(path string) (*rsa.PrivateKey, error) {
	data, err := os.ReadFile(path)
	if err == nil {
		block, _ := pem.Decode(data)
		if block == nil {
			return nil, errors.New("ADB 私钥不是有效的 PEM 文件")
		}
		if key, parseErr := x509.ParsePKCS1PrivateKey(block.Bytes); parseErr == nil {
			return key, nil
		}
		parsed, parseErr := x509.ParsePKCS8PrivateKey(block.Bytes)
		if parseErr != nil {
			return nil, fmt.Errorf("解析 ADB 私钥失败：%w", parseErr)
		}
		key, ok := parsed.(*rsa.PrivateKey)
		if !ok {
			return nil, errors.New("ADB 私钥不是 RSA 密钥")
		}
		return key, nil
	}
	if !errors.Is(err, os.ErrNotExist) {
		return nil, err
	}

	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		return nil, err
	}
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		return nil, fmt.Errorf("生成 ADB 私钥失败：%w", err)
	}
	encoded := pem.EncodeToMemory(&pem.Block{Type: "RSA PRIVATE KEY", Bytes: x509.MarshalPKCS1PrivateKey(key)})
	if err := os.WriteFile(path, encoded, 0600); err != nil {
		return nil, err
	}
	return key, nil
}

func fixedLittleEndian(value *big.Int, size int) []byte {
	result := make([]byte, size)
	bigEndian := value.Bytes()
	for index := 0; index < len(bigEndian) && index < size; index++ {
		result[index] = bigEndian[len(bigEndian)-1-index]
	}
	return result
}

func encodeAndroidPublicKey(publicKey *rsa.PublicKey, name string) ([]byte, error) {
	const modulusWords = 64
	const modulusBytes = modulusWords * 4
	if publicKey.N.BitLen() > modulusBytes*8 {
		return nil, errors.New("ADB RSA 公钥超过 2048 位")
	}

	wordModulus := new(big.Int).And(publicKey.N, new(big.Int).SetUint64(0xffffffff))
	twoTo32 := new(big.Int).Lsh(big.NewInt(1), 32)
	inverse := new(big.Int).ModInverse(wordModulus, twoTo32)
	if inverse == nil {
		return nil, errors.New("无法计算 ADB RSA n0inv")
	}
	n0inv := uint32(0 - inverse.Uint64())

	rSquared := new(big.Int).Exp(big.NewInt(2), big.NewInt(modulusBytes*16), publicKey.N)
	androidKey := make([]byte, 4+4+modulusBytes+modulusBytes+4)
	binary.LittleEndian.PutUint32(androidKey[0:4], modulusWords)
	binary.LittleEndian.PutUint32(androidKey[4:8], n0inv)
	copy(androidKey[8:8+modulusBytes], fixedLittleEndian(publicKey.N, modulusBytes))
	copy(androidKey[8+modulusBytes:8+modulusBytes*2], fixedLittleEndian(rSquared, modulusBytes))
	binary.LittleEndian.PutUint32(androidKey[8+modulusBytes*2:], uint32(publicKey.E))

	encoded := base64.StdEncoding.EncodeToString(androidKey) + " " + name
	return append([]byte(encoded), 0), nil
}

func signToken(privateKey *rsa.PrivateKey, token []byte) ([]byte, error) {
	if len(token) != crypto.SHA1.Size() {
		return nil, fmt.Errorf("ADB 认证令牌长度异常：%d", len(token))
	}
	return rsa.SignPKCS1v15(rand.Reader, privateKey, crypto.SHA1, token)
}

func connectADB(ctx context.Context, address string, privateKey *rsa.PrivateKey, deviceName string) (*adbConn, error) {
	dialer := net.Dialer{}
	rawConn, err := dialer.DialContext(ctx, "tcp", address)
	if err != nil {
		return nil, fmt.Errorf("连接电视 ADB 失败：%w", err)
	}
	conn := &adbConn{Conn: rawConn}
	if deadline, ok := ctx.Deadline(); ok {
		_ = conn.SetDeadline(deadline)
	}

	banner := append([]byte("host::features=shell_v2"), 0)
	if err := conn.writePacket(aCnxn, adbVersion, adbMaxPayload, banner); err != nil {
		conn.Close()
		return nil, err
	}

	sentSignature := false
	sentPublicKey := false
	for {
		incoming, err := conn.readPacket()
		if err != nil {
			conn.Close()
			if sentPublicKey {
				return nil, fmt.Errorf("等待电视确认 ADB 授权超时：%w", err)
			}
			return nil, fmt.Errorf("ADB 握手失败：%w", err)
		}

		switch incoming.command {
		case aCnxn:
			return conn, nil
		case aAuth:
			if incoming.arg0 != authToken {
				conn.Close()
				return nil, fmt.Errorf("不支持的 ADB AUTH 类型：%d", incoming.arg0)
			}
			if !sentSignature {
				signature, signErr := signToken(privateKey, incoming.payload)
				if signErr != nil {
					conn.Close()
					return nil, signErr
				}
				if err := conn.writePacket(aAuth, authSignature, 0, signature); err != nil {
					conn.Close()
					return nil, err
				}
				sentSignature = true
				continue
			}
			if !sentPublicKey {
				publicKey, keyErr := encodeAndroidPublicKey(&privateKey.PublicKey, deviceName)
				if keyErr != nil {
					conn.Close()
					return nil, keyErr
				}
				if err := conn.writePacket(aAuth, authPublicKey, 0, publicKey); err != nil {
					conn.Close()
					return nil, err
				}
				sentPublicKey = true
				continue
			}
			conn.Close()
			return nil, errors.New("电视未接受 ADB 公钥")
		default:
			conn.Close()
			return nil, fmt.Errorf("ADB 握手收到意外命令：0x%x", incoming.command)
		}
	}
}

func probeTCP(ctx context.Context, address string) error {
	dialer := net.Dialer{}
	conn, err := dialer.DialContext(ctx, "tcp", address)
	if err != nil {
		return fmt.Errorf("连接 TCP 端口失败：%w", err)
	}
	return conn.Close()
}

func runShell(conn *adbConn, localID uint32, command string, output io.Writer) error {
	destination := append([]byte("shell:"+command), 0)
	if err := conn.writePacket(aOpen, localID, 0, destination); err != nil {
		return err
	}

	var remoteID uint32
	for {
		incoming, err := conn.readPacket()
		if err != nil {
			return err
		}
		switch incoming.command {
		case aOkay:
			if incoming.arg1 == localID && remoteID == 0 {
				remoteID = incoming.arg0
			}
		case aWrte:
			if incoming.arg1 != localID {
				continue
			}
			if remoteID == 0 {
				remoteID = incoming.arg0
			}
			if _, err := output.Write(incoming.payload); err != nil {
				return err
			}
			if err := conn.writePacket(aOkay, localID, incoming.arg0, nil); err != nil {
				return err
			}
		case aClse:
			if incoming.arg1 == localID {
				if remoteID == 0 {
					remoteID = incoming.arg0
				}
				_ = conn.writePacket(aClse, localID, remoteID, nil)
				return nil
			}
		case aSync:
			continue
		default:
			return fmt.Errorf("ADB shell 收到意外命令：0x%x", incoming.command)
		}
	}
}

func parseScreenState(output string) string {
	for _, line := range strings.Split(output, "\n") {
		line = strings.TrimSpace(line)
		switch {
		case strings.HasPrefix(line, "mScreenState=ON"):
			return "ON"
		case strings.HasPrefix(line, "mScreenState=OFF"):
			return "OFF"
		}
	}
	return ""
}

func parseWakefulness(output string) string {
	for _, line := range strings.Split(output, "\n") {
		line = strings.TrimSpace(line)
		switch {
		case strings.HasPrefix(line, "mWakefulness=Awake"):
			return "ON"
		case strings.HasPrefix(line, "mWakefulness=Asleep"), strings.HasPrefix(line, "mWakefulness=Dozing"):
			return "OFF"
		}
	}
	return ""
}

const bootReasonMarker = "__M_UI_BOOT_REASON__"

func parseBootReason(output string) string {
	lines := strings.Split(output, "\n")
	for index, line := range lines {
		if strings.TrimSpace(line) != bootReasonMarker {
			continue
		}
		for _, candidate := range lines[index+1:] {
			if reason := strings.TrimSpace(candidate); reason != "" {
				return reason
			}
		}
	}
	return ""
}

func parsePowerTime(output, field string) (uint64, bool) {
	prefix := field + "="
	for _, line := range strings.Split(output, "\n") {
		line = strings.TrimSpace(line)
		if !strings.HasPrefix(line, prefix) {
			continue
		}
		var value uint64
		if _, err := fmt.Sscanf(line, prefix+"%d", &value); err == nil {
			return value, true
		}
	}
	return 0, false
}

func isQuietBootBeforeFirstWake(powerOutput string) bool {
	reason := strings.ToLower(parseBootReason(powerOutput))
	if !strings.Contains(reason, "reboot,quiet") {
		return false
	}
	lastWakeTime, hasLastWakeTime := parsePowerTime(powerOutput, "mLastWakeTime")
	lastSleepTime, hasLastSleepTime := parsePowerTime(powerOutput, "mLastSleepTime")
	return hasLastWakeTime && hasLastSleepTime && lastWakeTime == 0 && lastSleepTime == 0
}

func resolveScreenState(displayState, wakefulnessState string) string {
	if displayState == "OFF" || wakefulnessState == "OFF" {
		return "OFF"
	}
	if displayState == "ON" && wakefulnessState == "ON" {
		return "ON"
	}
	if displayState == "" {
		return wakefulnessState
	}
	if wakefulnessState == "" {
		return displayState
	}
	return ""
}

func resolveObservedScreenState(displayOutput, powerOutput string) string {
	state := resolveScreenState(
		parseScreenState(displayOutput),
		parseWakefulness(powerOutput),
	)
	if state == "ON" && isQuietBootBeforeFirstWake(powerOutput) {
		return "OFF"
	}
	return state
}

func readScreenState(conn *adbConn) (string, error) {
	var display bytes.Buffer
	if err := runShell(conn, 1, "dumpsys display", &display); err != nil {
		return "", err
	}

	var power bytes.Buffer
	if err := runShell(conn, 2, "dumpsys power; echo "+bootReasonMarker+"; getprop sys.boot.reason", &power); err != nil {
		return "", err
	}
	if state := resolveObservedScreenState(display.String(), power.String()); state != "" {
		return state, nil
	}
	return "", errors.New("未在电视系统信息中找到屏幕状态")
}

func defaultKeyPath() string {
	if value := os.Getenv("M_ADB_KEY"); value != "" {
		return value
	}
	return "/etc/m-ui/adbkey"
}

func usage() {
	fmt.Fprintln(os.Stderr, "用法：m-adb [-s IP:端口] [--timeout 时长] [--key 私钥路径] connect|get-state|probe|screen-state|shell [命令]")
}

func main() {
	serial := flag.String("s", "", "电视 ADB 地址")
	keyPath := flag.String("key", defaultKeyPath(), "ADB 私钥路径")
	deviceName := flag.String("name", "m-ui@router", "电视授权弹窗中显示的设备名")
	timeout := flag.Duration("timeout", 12*time.Second, "连接和授权超时")
	showVersion := flag.Bool("version", false, "显示版本")
	flag.Parse()

	if *showVersion {
		fmt.Printf("m-adb %s\n", programVersion)
		return
	}

	args := flag.Args()
	if len(args) == 0 {
		usage()
		os.Exit(2)
	}

	action := args[0]
	address := *serial
	if action == "connect" {
		if len(args) < 2 {
			usage()
			os.Exit(2)
		}
		address = args[1]
	}
	if address == "" {
		fmt.Fprintln(os.Stderr, "未指定电视 ADB 地址")
		os.Exit(2)
	}
	if !strings.Contains(address, ":") {
		address += ":5555"
	}

	ctx, cancel := context.WithTimeout(context.Background(), *timeout)
	defer cancel()
	if action == "probe" {
		if err := probeTCP(ctx, address); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		fmt.Println("open")
		return
	}

	privateKey, err := loadOrCreateKey(*keyPath)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	conn, err := connectADB(ctx, address, privateKey, *deviceName)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	defer conn.Close()

	switch action {
	case "connect":
		fmt.Printf("connected to %s\n", address)
	case "get-state":
		fmt.Println("device")
	case "screen-state":
		state, stateErr := readScreenState(conn)
		if stateErr != nil {
			fmt.Fprintln(os.Stderr, stateErr)
			os.Exit(1)
		}
		fmt.Println(state)
	case "shell":
		if len(args) < 2 {
			fmt.Fprintln(os.Stderr, "shell 命令不能为空")
			os.Exit(2)
		}
		if err := runShell(conn, 1, strings.Join(args[1:], " "), os.Stdout); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
	default:
		usage()
		os.Exit(2)
	}
}
