package gatewayruntime

import (
	"encoding/json"
	"net"
	"net/http"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/gorilla/websocket"
)

func TestManagerConnectAndRequest(t *testing.T) {
	server := newFakeGatewayServer(t)
	defer server.Close()

	manager := NewManager()
	manager.ReconnectDelay = 20 * time.Millisecond
	notifications := make([]map[string]any, 0, 8)
	var mu sync.Mutex
	notify := func(message map[string]any) {
		mu.Lock()
		defer mu.Unlock()
		notifications = append(notifications, message)
	}

	result := manager.Connect(buildTestConnectRequest(server.Port()), notify)
	if !result.OK {
		t.Fatalf("expected connect success, got %#v", result.Error)
	}
	if result.ReturnedDeviceToken != "device-token-1" {
		t.Fatalf("expected returned device token, got %#v", result.ReturnedDeviceToken)
	}

	requestResult := manager.Request(
		"runtime-1",
		"health",
		map[string]any{},
		2*time.Second,
		notify,
	)
	if !requestResult.OK {
		t.Fatalf("expected health success, got %#v", requestResult.Error)
	}
	payload, ok := requestResult.Payload.(map[string]any)
	if !ok || payload["status"] != "ok" {
		t.Fatalf("unexpected health payload %#v", requestResult.Payload)
	}

	mu.Lock()
	defer mu.Unlock()
	if len(notifications) == 0 {
		t.Fatalf("expected notifications during connect")
	}
}

func TestManagerReconnectsAfterSocketClose(t *testing.T) {
	server := newFakeGatewayServer(t)
	server.closeAfterConnect.Store(true)
	defer server.Close()

	manager := NewManager()
	manager.ReconnectDelay = 25 * time.Millisecond

	reconnected := make(chan struct{}, 1)
	notify := func(message map[string]any) {
		params := asMap(message["params"])
		if strings.TrimSpace(stringValue(message["method"])) != "xworkmate.gateway.snapshot" {
			return
		}
		snapshot := asMap(params["snapshot"])
		if snapshot["status"] == "connected" && server.ConnectCount() >= 2 {
			select {
			case reconnected <- struct{}{}:
			default:
			}
		}
	}

	result := manager.Connect(buildTestConnectRequest(server.Port()), notify)
	if !result.OK {
		t.Fatalf("expected connect success, got %#v", result.Error)
	}

	select {
	case <-reconnected:
	case <-time.After(3 * time.Second):
		t.Fatalf("expected reconnect to complete; connect count=%d", server.ConnectCount())
	}
}

func TestManagerSuppressesReconnectForPairingRequired(t *testing.T) {
	server := newFakeGatewayServer(t)
	server.connectErrorCode = "NOT_PAIRED"
	server.connectErrorDetailCode = "PAIRING_REQUIRED"
	defer server.Close()

	manager := NewManager()
	manager.ReconnectDelay = 20 * time.Millisecond
	result := manager.Connect(buildTestConnectRequest(server.Port()), func(map[string]any) {})
	if result.OK {
		t.Fatalf("expected connect failure")
	}
	time.Sleep(120 * time.Millisecond)
	if server.ConnectCount() != 1 {
		t.Fatalf("expected reconnect suppression, got %d connect attempts", server.ConnectCount())
	}
}

type fakeGatewayServer struct {
	server                 *http.Server
	listener               net.Listener
	connectCount           atomic.Int32
	closeAfterConnect      atomic.Bool
	connectErrorCode       string
	connectErrorDetailCode string
}

func newFakeGatewayServer(t *testing.T) *fakeGatewayServer {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	fake := &fakeGatewayServer{listener: listener}
	upgrader := websocket.Upgrader{CheckOrigin: func(*http.Request) bool { return true }}
	mux := http.NewServeMux()
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			return
		}
		defer conn.Close()
		_ = conn.WriteJSON(map[string]any{
			"type":  "event",
			"event": "connect.challenge",
			"payload": map[string]any{
				"nonce": "nonce-1",
			},
		})
		for {
			_, payload, err := conn.ReadMessage()
			if err != nil {
				return
			}
			var frame map[string]any
			if err := json.Unmarshal(payload, &frame); err != nil {
				continue
			}
			if frame["type"] != "req" {
				continue
			}
			id := frame["id"]
			method := stringValue(frame["method"])
			switch method {
			case "connect":
				fake.connectCount.Add(1)
				if fake.connectErrorCode != "" {
					_ = conn.WriteJSON(map[string]any{
						"type": "res",
						"id":   id,
						"ok":   false,
						"error": map[string]any{
							"code":    fake.connectErrorCode,
							"message": "connect failed",
							"details": map[string]any{
								"code": fake.connectErrorDetailCode,
							},
						},
					})
					continue
				}
				_ = conn.WriteJSON(map[string]any{
					"type": "res",
					"id":   id,
					"ok":   true,
					"payload": map[string]any{
						"server": map[string]any{"host": "127.0.0.1"},
						"snapshot": map[string]any{
							"sessionDefaults": map[string]any{"mainSessionKey": "main"},
						},
						"auth": map[string]any{
							"role":        "operator",
							"scopes":      defaultOperatorScopes,
							"deviceToken": "device-token-1",
						},
					},
				})
				if fake.closeAfterConnect.Load() && fake.connectCount.Load() == 1 {
					go func() {
						time.Sleep(20 * time.Millisecond)
						_ = conn.Close()
					}()
				}
			case "health":
				_ = conn.WriteJSON(map[string]any{
					"type": "res",
					"id":   id,
					"ok":   true,
					"payload": map[string]any{
						"status": "ok",
					},
				})
			default:
				_ = conn.WriteJSON(map[string]any{
					"type":    "res",
					"id":      id,
					"ok":      true,
					"payload": map[string]any{},
				})
			}
		}
	})
	fake.server = &http.Server{Handler: mux}
	go func() {
		_ = fake.server.Serve(listener)
	}()
	return fake
}

func (f *fakeGatewayServer) Port() int {
	return f.listener.Addr().(*net.TCPAddr).Port
}

func (f *fakeGatewayServer) ConnectCount() int {
	return int(f.connectCount.Load())
}

func (f *fakeGatewayServer) Close() {
	_ = f.server.Close()
}

func buildTestConnectRequest(port int) ConnectRequest {
	return ConnectRequest{
		RuntimeID: "runtime-1",
		Mode:      "remote",
		ClientID:  "openclaw-macos",
		Locale:    "en_US",
		UserAgent: "XWorkmate/1.0.0",
		Endpoint: Endpoint{
			Host: "127.0.0.1",
			Port: port,
			TLS:  false,
		},
		ConnectAuthMode:    "shared-token",
		ConnectAuthFields:  []string{"token"},
		ConnectAuthSources: []string{"shared:form"},
		HasSharedAuth:      true,
		HasDeviceToken:     false,
		PackageInfo: PackageInfo{
			AppName: "XWorkmate",
			Version: "1.0.0",
		},
		DeviceInfo: DeviceInfo{
			Platform:        "macos",
			PlatformVersion: "14.0",
			DeviceFamily:    "Mac",
			ModelIdentifier: "Mac14,5",
		},
		Identity: DeviceIdentity{
			DeviceID:            "device-1",
			PublicKeyBase64URL:  "tl4fnKW7VLD0Cl4lQTu2CEgHPs4PWAX7eVgWfWQWk2Q",
			PrivateKeyBase64URL: "dr7GfMKoO-lJBtgA0dE5m6f_X4kEFsxChDc7mW8mkXu2Xh-cpbsUsPQKXiVBO7YISAc-zg9YBft5WBZ9ZBaTZA",
		},
		Auth: AuthConfig{
			Token: "shared-token",
		},
	}
}
