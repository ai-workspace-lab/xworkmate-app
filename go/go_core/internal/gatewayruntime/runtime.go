package gatewayruntime

import (
	"crypto/ed25519"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/gorilla/websocket"

	"xworkmate/go_core/internal/shared"
)

type remoteResponse struct {
	Type    string         `json:"type"`
	ID      string         `json:"id"`
	OK      bool           `json:"ok"`
	Payload any            `json:"payload"`
	Error   map[string]any `json:"error"`
}

type runtimeSnapshot struct {
	Status              string
	Mode                string
	StatusText          string
	ServerName          string
	RemoteAddress       string
	MainSessionKey      string
	LastError           string
	LastErrorCode       string
	LastErrorDetailCode string
	LastConnectedAtMs   int64
	DeviceID            string
	AuthRole            string
	AuthScopes          []string
	ConnectAuthMode     string
	ConnectAuthFields   []string
	ConnectAuthSources  []string
	HasSharedAuth       bool
	HasDeviceToken      bool
	HealthPayload       map[string]any
	StatusPayload       map[string]any
}

func (s runtimeSnapshot) Map() map[string]any {
	payload := map[string]any{
		"status":             s.Status,
		"mode":               s.Mode,
		"statusText":         s.StatusText,
		"authScopes":         append([]string(nil), s.AuthScopes...),
		"connectAuthFields":  append([]string(nil), s.ConnectAuthFields...),
		"connectAuthSources": append([]string(nil), s.ConnectAuthSources...),
		"hasSharedAuth":      s.HasSharedAuth,
		"hasDeviceToken":     s.HasDeviceToken,
	}
	if s.ServerName != "" {
		payload["serverName"] = s.ServerName
	}
	if s.RemoteAddress != "" {
		payload["remoteAddress"] = s.RemoteAddress
	}
	if s.MainSessionKey != "" {
		payload["mainSessionKey"] = s.MainSessionKey
	}
	if s.LastError != "" {
		payload["lastError"] = s.LastError
	}
	if s.LastErrorCode != "" {
		payload["lastErrorCode"] = s.LastErrorCode
	}
	if s.LastErrorDetailCode != "" {
		payload["lastErrorDetailCode"] = s.LastErrorDetailCode
	}
	if s.LastConnectedAtMs > 0 {
		payload["lastConnectedAtMs"] = s.LastConnectedAtMs
	}
	if s.DeviceID != "" {
		payload["deviceId"] = s.DeviceID
	}
	if s.AuthRole != "" {
		payload["authRole"] = s.AuthRole
	}
	if s.ConnectAuthMode != "" {
		payload["connectAuthMode"] = s.ConnectAuthMode
	}
	if len(s.HealthPayload) > 0 {
		payload["healthPayload"] = s.HealthPayload
	}
	if len(s.StatusPayload) > 0 {
		payload["statusPayload"] = s.StatusPayload
	}
	return payload
}

type Manager struct {
	mu sync.Mutex

	sessions map[string]*session

	ReconnectDelay   time.Duration
	ConnectTimeout   time.Duration
	ChallengeTimeout time.Duration
}

func NewManager() *Manager {
	return &Manager{
		sessions:         make(map[string]*session),
		ReconnectDelay:   defaultReconnectDelay,
		ConnectTimeout:   defaultConnectTimeout,
		ChallengeTimeout: defaultChallengeWait,
	}
}

func (m *Manager) Connect(
	request ConnectRequest,
	notify func(map[string]any),
) ConnectResult {
	runtimeID := strings.TrimSpace(request.RuntimeID)
	if runtimeID == "" {
		return ConnectResult{
			OK: false,
			Error: (&GatewayError{
				Message: "runtimeId is required",
				Code:    "INVALID_RUNTIME_ID",
			}).Map(),
		}
	}

	m.mu.Lock()
	current := m.sessions[runtimeID]
	if current == nil {
		current = newSession(m, runtimeID)
		m.sessions[runtimeID] = current
	}
	m.mu.Unlock()

	current.configure(request, notify)
	return current.connect()
}

func (m *Manager) Request(
	runtimeID string,
	method string,
	params map[string]any,
	timeout time.Duration,
	notify func(map[string]any),
) RequestResult {
	current := m.lookup(runtimeID)
	if current == nil {
		return RequestResult{
			OK: false,
			Error: (&GatewayError{
				Message: "gateway not connected",
				Code:    "OFFLINE",
			}).Map(),
		}
	}
	current.setNotify(notify)
	return current.request(method, params, timeout)
}

func (m *Manager) RequestByMode(
	mode string,
	method string,
	params map[string]any,
	timeout time.Duration,
	notify func(map[string]any),
) RequestResult {
	current := m.lookupConnectedByMode(mode)
	if current == nil {
		return RequestResult{
			OK: false,
			Error: (&GatewayError{
				Message: "gateway not connected",
				Code:    "OFFLINE",
			}).Map(),
		}
	}
	current.setNotify(notify)
	return current.request(method, params, timeout)
}

func (m *Manager) Disconnect(runtimeID string, notify func(map[string]any)) {
	current := m.lookup(runtimeID)
	if current == nil {
		return
	}
	current.setNotify(notify)
	current.disconnect()
}

func (m *Manager) lookup(runtimeID string) *session {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.sessions[strings.TrimSpace(runtimeID)]
}

func (m *Manager) lookupConnectedByMode(mode string) *session {
	normalizedMode := strings.TrimSpace(mode)
	m.mu.Lock()
	defer m.mu.Unlock()
	for _, current := range m.sessions {
		if current == nil {
			continue
		}
		current.mu.Lock()
		connected := current.snapshot.Status == "connected"
		currentMode := current.snapshot.Mode
		current.mu.Unlock()
		if connected && strings.TrimSpace(currentMode) == normalizedMode {
			return current
		}
	}
	return nil
}

type session struct {
	manager   *Manager
	runtimeID string

	mu                sync.Mutex
	writeMu           sync.Mutex
	notify            func(map[string]any)
	config            ConnectRequest
	snapshot          runtimeSnapshot
	conn              *websocket.Conn
	pending           map[string]chan remoteResponse
	requestSeq        int64
	reconnectTimer    *time.Timer
	manualDisconnect  bool
	suppressReconnect bool
	closed            bool
	challengeCh       chan string
}

func newSession(manager *Manager, runtimeID string) *session {
	return &session{
		manager:   manager,
		runtimeID: runtimeID,
		pending:   make(map[string]chan remoteResponse),
	}
}

func (s *session) configure(request ConnectRequest, notify func(map[string]any)) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.notify = notify
	s.config = request
	s.manualDisconnect = false
	s.suppressReconnect = false
	s.closed = false
	s.stopReconnectLocked()
	s.snapshot = runtimeSnapshot{
		Status:             "offline",
		Mode:               request.Mode,
		StatusText:         "Offline",
		DeviceID:           request.Identity.DeviceID,
		ConnectAuthMode:    request.ConnectAuthMode,
		ConnectAuthFields:  append([]string(nil), request.ConnectAuthFields...),
		ConnectAuthSources: append([]string(nil), request.ConnectAuthSources...),
		HasSharedAuth:      request.HasSharedAuth,
		HasDeviceToken:     request.HasDeviceToken,
	}
}

func (s *session) setNotify(notify func(map[string]any)) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.notify = notify
}

func (s *session) connect() ConnectResult {
	s.appendLog(
		"info",
		"connect",
		fmt.Sprintf(
			"attempt %s:%d tls:%t | auth: %s",
			s.config.Endpoint.Host,
			s.config.Endpoint.Port,
			s.config.Endpoint.TLS,
			formatConnectAuthSummary(
				s.config.ConnectAuthMode,
				s.config.ConnectAuthFields,
				s.config.ConnectAuthSources,
			),
		),
	)
	s.updateSnapshot(func(snapshot *runtimeSnapshot) {
		snapshot.Status = "connecting"
		snapshot.StatusText = "Connecting…"
		snapshot.RemoteAddress = fmt.Sprintf(
			"%s:%d",
			s.config.Endpoint.Host,
			s.config.Endpoint.Port,
		)
		snapshot.LastError = ""
		snapshot.LastErrorCode = ""
		snapshot.LastErrorDetailCode = ""
	})

	result, gatewayErr := s.connectAttempt()
	if gatewayErr == nil {
		return result
	}
	s.handleConnectFailure(gatewayErr)
	return ConnectResult{
		OK:       false,
		Snapshot: s.snapshotMap(),
		Error:    gatewayErr.Map(),
	}
}

func (s *session) connectAttempt() (ConnectResult, *GatewayError) {
	url := fmt.Sprintf(
		"%s://%s:%d",
		resolveRemoteScheme(s.config.Endpoint.TLS),
		s.config.Endpoint.Host,
		s.config.Endpoint.Port,
	)
	dialer := websocket.Dialer{
		HandshakeTimeout: s.manager.ConnectTimeout,
		Proxy:            http.ProxyFromEnvironment,
	}
	conn, _, err := dialer.Dial(url, nil)
	if err != nil {
		return ConnectResult{}, &GatewayError{
			Message: err.Error(),
			Code:    "SOCKET_FAILURE",
		}
	}

	challengeCh := make(chan string, 1)
	s.mu.Lock()
	s.conn = conn
	s.challengeCh = challengeCh
	s.mu.Unlock()
	go s.readLoop(conn, challengeCh)

	var nonce string
	select {
	case nonce = <-challengeCh:
	case <-time.After(s.manager.ChallengeTimeout):
		s.closeConn(conn)
		return ConnectResult{}, &GatewayError{
			Message: "connect challenge timeout",
			Code:    "CONNECT_CHALLENGE_TIMEOUT",
		}
	}

	params, gatewayErr := buildConnectParams(s.config, nonce)
	if gatewayErr != nil {
		s.closeConn(conn)
		return ConnectResult{}, gatewayErr
	}
	requestResult := s.requestRemote("connect", params, 12*time.Second, false)
	if !requestResult.OK {
		s.closeConn(conn)
		return ConnectResult{}, mapToGatewayError(requestResult.Error, "connect failed")
	}

	payload, _ := requestResult.Payload.(map[string]any)
	auth := asMap(payload["auth"])
	server := asMap(payload["server"])
	snapshotPayload := asMap(payload["snapshot"])
	sessionDefaults := asMap(snapshotPayload["sessionDefaults"])
	returnedDeviceToken := strings.TrimSpace(stringValue(auth["deviceToken"]))
	if returnedDeviceToken != "" {
		s.mu.Lock()
		s.config.Auth.DeviceToken = returnedDeviceToken
		s.mu.Unlock()
	}
	negotiatedScopes := stringSlice(auth["scopes"])
	negotiatedRole := strings.TrimSpace(stringValue(auth["role"]))
	if negotiatedRole == "" {
		negotiatedRole = "operator"
	}
	s.updateSnapshot(func(snapshot *runtimeSnapshot) {
		snapshot.Status = "connected"
		snapshot.StatusText = "Connected"
		snapshot.ServerName = strings.TrimSpace(stringValue(server["host"]))
		snapshot.RemoteAddress = fmt.Sprintf(
			"%s:%d",
			s.config.Endpoint.Host,
			s.config.Endpoint.Port,
		)
		snapshot.MainSessionKey = strings.TrimSpace(
			stringValue(sessionDefaults["mainSessionKey"]),
		)
		if snapshot.MainSessionKey == "" {
			snapshot.MainSessionKey = "main"
		}
		snapshot.LastConnectedAtMs = time.Now().UnixMilli()
		snapshot.AuthRole = negotiatedRole
		snapshot.AuthScopes = negotiatedScopes
		snapshot.HasDeviceToken =
			returnedDeviceToken != "" || s.config.Auth.DeviceToken != ""
		snapshot.LastError = ""
		snapshot.LastErrorCode = ""
		snapshot.LastErrorDetailCode = ""
	})
	s.appendLog(
		"info",
		"connect",
		fmt.Sprintf(
			"connected %s:%d | role: %s | scopes: %d",
			s.config.Endpoint.Host,
			s.config.Endpoint.Port,
			negotiatedRole,
			len(negotiatedScopes),
		),
	)
	return ConnectResult{
		OK:                  true,
		Snapshot:            s.snapshotMap(),
		Auth:                auth,
		ReturnedDeviceToken: returnedDeviceToken,
	}, nil
}

func (s *session) request(
	method string,
	params map[string]any,
	timeout time.Duration,
) RequestResult {
	return s.requestRemote(method, params, timeout, true)
}

func (s *session) requestRemote(
	method string,
	params map[string]any,
	timeout time.Duration,
	requireConnected bool,
) RequestResult {
	if timeout <= 0 {
		timeout = defaultRequestTimeout
	}

	s.mu.Lock()
	conn := s.conn
	connected := s.snapshot.Status == "connected"
	if conn == nil || (requireConnected && !connected) {
		s.mu.Unlock()
		s.appendLog("warn", "rpc", fmt.Sprintf("blocked request %s | offline", method))
		return RequestResult{
			OK: false,
			Error: (&GatewayError{
				Message: "gateway not connected",
				Code:    "OFFLINE",
			}).Map(),
		}
	}
	requestID := fmt.Sprintf("%d-%d", time.Now().UnixMicro(), s.requestSeq)
	s.requestSeq++
	responseCh := make(chan remoteResponse, 1)
	s.pending[requestID] = responseCh
	s.mu.Unlock()

	frame := map[string]any{
		"type":   "req",
		"id":     requestID,
		"method": method,
	}
	if len(params) > 0 {
		frame["params"] = params
	}

	s.writeMu.Lock()
	writeErr := conn.WriteJSON(frame)
	s.writeMu.Unlock()
	if writeErr != nil {
		s.mu.Lock()
		delete(s.pending, requestID)
		s.mu.Unlock()
		return RequestResult{
			OK: false,
			Error: (&GatewayError{
				Message: writeErr.Error(),
				Code:    "SOCKET_FAILURE",
			}).Map(),
		}
	}

	select {
	case response := <-responseCh:
		s.mu.Lock()
		delete(s.pending, requestID)
		s.mu.Unlock()
		if !response.OK {
			gatewayErr := parseRemoteError(response.Error)
			if !shouldAutoReconnectForCodes(
				gatewayErr.Code,
				gatewayErr.DetailCode(),
			) {
				s.mu.Lock()
				s.suppressReconnect = true
				s.mu.Unlock()
			}
			s.appendLog(
				"error",
				"rpc",
				fmt.Sprintf(
					"request failed | code: %s | detail: %s | message: %s",
					fallbackText(gatewayErr.Code, "unknown"),
					fallbackText(gatewayErr.DetailCode(), "none"),
					fallbackText(gatewayErr.Message, "gateway request failed"),
				),
			)
			return RequestResult{
				OK:    false,
				Error: gatewayErr.Map(),
			}
		}
		return RequestResult{
			OK:      true,
			Payload: response.Payload,
		}
	case <-time.After(timeout):
		s.mu.Lock()
		delete(s.pending, requestID)
		s.mu.Unlock()
		return RequestResult{
			OK: false,
			Error: (&GatewayError{
				Message: method + " request timeout",
				Code:    "RPC_TIMEOUT",
			}).Map(),
		}
	}
}

func (s *session) disconnect() {
	s.mu.Lock()
	s.manualDisconnect = true
	s.stopReconnectLocked()
	conn := s.conn
	s.conn = nil
	pending := s.takePendingLocked()
	s.snapshot = runtimeSnapshot{
		Status:             "offline",
		Mode:               s.snapshot.Mode,
		StatusText:         "Offline",
		DeviceID:           s.snapshot.DeviceID,
		AuthRole:           s.snapshot.AuthRole,
		AuthScopes:         append([]string(nil), s.snapshot.AuthScopes...),
		ConnectAuthMode:    s.snapshot.ConnectAuthMode,
		ConnectAuthFields:  append([]string(nil), s.snapshot.ConnectAuthFields...),
		ConnectAuthSources: append([]string(nil), s.snapshot.ConnectAuthSources...),
		HasSharedAuth:      s.snapshot.HasSharedAuth,
		HasDeviceToken:     s.snapshot.HasDeviceToken,
	}
	s.mu.Unlock()

	s.appendLog("info", "connect", "manual disconnect")
	for _, ch := range pending {
		ch <- remoteResponse{
			OK: false,
			Error: (&GatewayError{
				Message: "socket reset",
				Code:    "SOCKET_RESET",
			}).Map(),
		}
	}
	s.emitSnapshot()
	if conn != nil {
		_ = conn.Close()
	}
}

func (s *session) readLoop(conn *websocket.Conn, challengeCh chan string) {
	for {
		_, payload, err := conn.ReadMessage()
		if err != nil {
			s.onConnLost(conn, err)
			return
		}
		var decoded map[string]any
		if err := json.Unmarshal(payload, &decoded); err != nil {
			continue
		}
		switch strings.TrimSpace(stringValue(decoded["type"])) {
		case "event":
			event := strings.TrimSpace(stringValue(decoded["event"]))
			body := asMap(decoded["payload"])
			if event == "connect.challenge" {
				select {
				case challengeCh <- strings.TrimSpace(stringValue(body["nonce"])):
				default:
				}
				s.appendLog("debug", "connect", "challenge received")
				continue
			}
			s.handleEvent(event, decoded, body)
		case "res":
			response := remoteResponse{
				Type:    "res",
				ID:      strings.TrimSpace(stringValue(decoded["id"])),
				OK:      boolValue(decoded["ok"]),
				Payload: decoded["payload"],
				Error:   asMap(decoded["error"]),
			}
			s.mu.Lock()
			responseCh := s.pending[response.ID]
			s.mu.Unlock()
			if responseCh != nil {
				responseCh <- response
			}
		}
	}
}

func (s *session) handleEvent(
	event string,
	decoded map[string]any,
	payload map[string]any,
) {
	switch event {
	case "health":
		s.updateSnapshot(func(snapshot *runtimeSnapshot) {
			snapshot.HealthPayload = payload
		})
		s.appendLog("debug", "health", "push health update")
	case "device.pair.requested", "device.pair.resolved":
		s.appendLog(
			"info",
			"pairing",
			fmt.Sprintf(
				"%s | request: %s | device: %s",
				event,
				fallbackText(strings.TrimSpace(stringValue(payload["requestId"])), "unknown"),
				fallbackText(strings.TrimSpace(stringValue(payload["deviceId"])), "unknown"),
			),
		)
	case "seqGap":
		s.appendLog("warn", "sync", "sequence gap detected")
	}
	if normalized := normalizeChatRunEvent(event, payload); len(normalized) > 0 {
		s.emitNotification(
			"xworkmate.gateway.push",
			map[string]any{
				"runtimeId": s.runtimeID,
				"event": map[string]any{
					"event":    "chat.run",
					"payload":  normalized,
					"sequence": intValue(decoded["seq"]),
				},
			},
		)
	}
	s.emitNotification(
		"xworkmate.gateway.push",
		map[string]any{
			"runtimeId": s.runtimeID,
			"event": map[string]any{
				"event":    event,
				"payload":  payload,
				"sequence": intValue(decoded["seq"]),
			},
		},
	)
}

func (s *session) onConnLost(conn *websocket.Conn, err error) {
	s.mu.Lock()
	if s.conn != conn {
		s.mu.Unlock()
		return
	}
	s.conn = nil
	pending := s.takePendingLocked()
	manualDisconnect := s.manualDisconnect
	suppressReconnect := s.suppressReconnect
	closed := s.closed
	s.mu.Unlock()

	for _, ch := range pending {
		ch <- remoteResponse{
			OK: false,
			Error: (&GatewayError{
				Message: "socket closed",
				Code:    "SOCKET_CLOSED",
			}).Map(),
		}
	}
	if manualDisconnect || suppressReconnect || closed {
		s.appendLog(
			"warn",
			"socket",
			fmt.Sprintf(
				"closed without reconnect | manual: %t | suppressed: %t",
				manualDisconnect,
				suppressReconnect,
			),
		)
		return
	}
	s.appendLog("warn", "socket", "closed by gateway")
	s.updateSnapshot(func(snapshot *runtimeSnapshot) {
		snapshot.Status = "error"
		snapshot.StatusText = "Disconnected"
		snapshot.LastError = "Gateway connection closed"
		snapshot.LastErrorCode = "SOCKET_CLOSED"
		snapshot.LastErrorDetailCode = ""
	})
	s.scheduleReconnect()
}

func (s *session) handleConnectFailure(err *GatewayError) {
	if !shouldAutoReconnectForCodes(err.Code, err.DetailCode()) {
		s.mu.Lock()
		s.suppressReconnect = true
		s.mu.Unlock()
		s.appendLog(
			"warn",
			"socket",
			fmt.Sprintf(
				"auto reconnect suppressed | code: %s | detail: %s",
				fallbackText(err.Code, "unknown"),
				fallbackText(err.DetailCode(), "none"),
			),
		)
	} else {
		s.appendLog(
			"warn",
			"socket",
			fmt.Sprintf(
				"scheduling reconnect in 2s | code: %s",
				fallbackText(err.Code, "unknown"),
			),
		)
		s.scheduleReconnect()
	}
	s.appendLog(
		"error",
		"connect",
		fmt.Sprintf(
			"failed %s:%d | code: %s | detail: %s | message: %s",
			s.config.Endpoint.Host,
			s.config.Endpoint.Port,
			fallbackText(err.Code, "unknown"),
			fallbackText(err.DetailCode(), "none"),
			err.Message,
		),
	)
	s.updateSnapshot(func(snapshot *runtimeSnapshot) {
		snapshot.Status = "error"
		snapshot.StatusText = "Connection failed"
		snapshot.LastError = err.Message
		snapshot.LastErrorCode = err.Code
		snapshot.LastErrorDetailCode = err.DetailCode()
		snapshot.HasDeviceToken = s.config.Auth.DeviceToken != ""
	})
}

func (s *session) scheduleReconnect() {
	s.mu.Lock()
	if s.manualDisconnect || s.suppressReconnect || s.closed {
		s.mu.Unlock()
		return
	}
	s.stopReconnectLocked()
	delay := s.manager.ReconnectDelay
	if delay <= 0 {
		delay = defaultReconnectDelay
	}
	s.reconnectTimer = time.AfterFunc(delay, func() {
		s.appendLog(
			"info",
			"socket",
			fmt.Sprintf(
				"reconnect firing | host: %s | port: %d",
				resolveReconnectHostLabel(s.config.Endpoint.Host),
				s.config.Endpoint.Port,
			),
		)
		if _, err := s.connectAttempt(); err != nil {
			s.handleConnectFailure(err)
		}
	})
	s.mu.Unlock()
}

func (s *session) stopReconnectLocked() {
	if s.reconnectTimer != nil {
		s.reconnectTimer.Stop()
		s.reconnectTimer = nil
	}
}

func (s *session) closeConn(conn *websocket.Conn) {
	if conn != nil {
		_ = conn.Close()
	}
}

func (s *session) takePendingLocked() map[string]chan remoteResponse {
	pending := s.pending
	s.pending = make(map[string]chan remoteResponse)
	return pending
}

func (s *session) updateSnapshot(update func(snapshot *runtimeSnapshot)) {
	s.mu.Lock()
	update(&s.snapshot)
	s.mu.Unlock()
	s.emitSnapshot()
}

func (s *session) snapshotMap() map[string]any {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.snapshot.Map()
}

func (s *session) emitSnapshot() {
	s.emitNotification(
		"xworkmate.gateway.snapshot",
		map[string]any{
			"runtimeId": s.runtimeID,
			"snapshot":  s.snapshotMap(),
		},
	)
}

func (s *session) appendLog(level string, category string, message string) {
	entry := map[string]any{
		"timestampMs": time.Now().UnixMilli(),
		"level":       level,
		"category":    category,
		"message":     message,
	}
	s.emitNotification(
		"xworkmate.gateway.log",
		map[string]any{
			"runtimeId": s.runtimeID,
			"log":       entry,
		},
	)
}

func (s *session) emitNotification(method string, params map[string]any) {
	s.mu.Lock()
	notify := s.notify
	s.mu.Unlock()
	if notify == nil {
		return
	}
	notify(shared.NotificationEnvelope(method, params))
}

func buildConnectParams(
	request ConnectRequest,
	nonce string,
) (map[string]any, *GatewayError) {
	signedAt := time.Now().UnixMilli()
	signaturePayload := buildDeviceAuthPayloadV3(
		request.Identity.DeviceID,
		request.ClientID,
		"ui",
		"operator",
		defaultOperatorScopes,
		signedAt,
		firstNonEmpty(request.Auth.Token, request.Auth.DeviceToken),
		nonce,
		request.DeviceInfo.PlatformLabel(),
		request.DeviceInfo.DeviceFamily,
	)
	signature, err := signPayload(
		request.Identity.PrivateKeyBase64URL,
		signaturePayload,
	)
	if err != nil {
		return nil, &GatewayError{
			Message: err.Error(),
			Code:    "DEVICE_IDENTITY_SIGN_FAILED",
		}
	}

	result := map[string]any{
		"minProtocol": defaultProtocolVersion,
		"maxProtocol": defaultProtocolVersion,
		"client": map[string]any{
			"id":              request.ClientID,
			"displayName":     strings.TrimSpace(request.PackageInfo.AppName) + " " + strings.TrimSpace(request.DeviceInfo.DeviceFamily),
			"version":         request.PackageInfo.Version,
			"platform":        request.DeviceInfo.PlatformLabel(),
			"deviceFamily":    request.DeviceInfo.DeviceFamily,
			"modelIdentifier": request.DeviceInfo.ModelIdentifier,
			"mode":            "ui",
			"instanceId":      request.ClientID + "-" + trimPrefix(request.Identity.DeviceID, 8),
		},
		"caps":        []string{"tool-events"},
		"commands":    []string{},
		"permissions": map[string]bool{},
		"role":        "operator",
		"scopes":      append([]string(nil), defaultOperatorScopes...),
		"locale":      request.Locale,
		"userAgent":   request.UserAgent,
		"device": map[string]any{
			"id":        request.Identity.DeviceID,
			"publicKey": request.Identity.PublicKeyBase64URL,
			"signature": signature,
			"signedAt":  signedAt,
			"nonce":     nonce,
		},
	}
	if request.Auth.Token != "" || request.Auth.DeviceToken != "" || request.Auth.Password != "" {
		auth := map[string]any{}
		if request.Auth.Token != "" {
			auth["token"] = request.Auth.Token
		}
		if request.Auth.DeviceToken != "" {
			auth["deviceToken"] = request.Auth.DeviceToken
		}
		if request.Auth.Password != "" {
			auth["password"] = request.Auth.Password
		}
		result["auth"] = auth
	}
	return result, nil
}

func signPayload(privateKeyBase64URL string, payload string) (string, error) {
	privateKeyBytes, err := decodeBase64URL(privateKeyBase64URL)
	if err != nil {
		return "", err
	}
	var privateKey ed25519.PrivateKey
	switch len(privateKeyBytes) {
	case ed25519.PrivateKeySize:
		privateKey = ed25519.PrivateKey(privateKeyBytes)
	case ed25519.SeedSize:
		privateKey = ed25519.NewKeyFromSeed(privateKeyBytes)
	default:
		return "", fmt.Errorf("unsupported Ed25519 private key length: %d", len(privateKeyBytes))
	}
	signature := ed25519.Sign(privateKey, []byte(payload))
	return encodeBase64URL(signature), nil
}

func buildDeviceAuthPayloadV3(
	deviceID string,
	clientID string,
	clientMode string,
	role string,
	scopes []string,
	signedAt int64,
	token string,
	nonce string,
	platform string,
	deviceFamily string,
) string {
	parts := []string{
		"v3",
		deviceID,
		clientID,
		clientMode,
		role,
		strings.Join(scopes, ","),
		fmt.Sprintf("%d", signedAt),
		token,
		nonce,
		normalizeMetadataForAuth(platform),
		normalizeMetadataForAuth(deviceFamily),
	}
	return strings.Join(parts, "|")
}

func normalizeMetadataForAuth(value string) string {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return ""
	}
	var builder strings.Builder
	builder.Grow(len(trimmed))
	for _, r := range trimmed {
		if r >= 'A' && r <= 'Z' {
			builder.WriteRune(r + 32)
			continue
		}
		builder.WriteRune(r)
	}
	return builder.String()
}

func shouldAutoReconnectForCodes(code string, detailCode string) bool {
	resolvedCode := strings.ToUpper(strings.TrimSpace(code))
	resolvedDetail := strings.ToUpper(strings.TrimSpace(detailCode))
	nonRetryableCodes := map[string]bool{
		"INVALID_REQUEST": true,
		"UNAUTHORIZED":    true,
		"NOT_PAIRED":      true,
		"AUTH_REQUIRED":   true,
	}
	nonRetryableDetailCodes := map[string]bool{
		"AUTH_REQUIRED":                       true,
		"AUTH_UNAUTHORIZED":                   true,
		"AUTH_TOKEN_MISSING":                  true,
		"AUTH_TOKEN_MISMATCH":                 true,
		"AUTH_PASSWORD_MISSING":               true,
		"AUTH_PASSWORD_MISMATCH":              true,
		"AUTH_DEVICE_TOKEN_MISMATCH":          true,
		"PAIRING_REQUIRED":                    true,
		"DEVICE_IDENTITY_REQUIRED":            true,
		"CONTROL_UI_DEVICE_IDENTITY_REQUIRED": true,
	}
	if nonRetryableCodes[resolvedCode] {
		return false
	}
	if nonRetryableDetailCodes[resolvedDetail] {
		return false
	}
	return true
}

func parseRemoteError(errorPayload map[string]any) *GatewayError {
	return &GatewayError{
		Message: fallbackText(strings.TrimSpace(stringValue(errorPayload["message"])), "gateway request failed"),
		Code:    strings.TrimSpace(stringValue(errorPayload["code"])),
		Details: asMap(errorPayload["details"]),
	}
}

func mapToGatewayError(errorPayload map[string]any, fallback string) *GatewayError {
	if len(errorPayload) == 0 {
		return &GatewayError{Message: fallback}
	}
	return &GatewayError{
		Message: fallbackText(strings.TrimSpace(stringValue(errorPayload["message"])), fallback),
		Code:    strings.TrimSpace(stringValue(errorPayload["code"])),
		Details: asMap(errorPayload["details"]),
	}
}

func resolveRemoteScheme(tls bool) string {
	if tls {
		return "wss"
	}
	return "ws"
}

func resolveReconnectHostLabel(host string) string {
	host = strings.TrimSpace(host)
	if host == "" {
		return "setup-code"
	}
	return host
}

func formatConnectAuthSummary(mode string, fields []string, sources []string) string {
	resolvedFields := "none"
	if len(fields) > 0 {
		resolvedFields = strings.Join(fields, ", ")
	}
	resolvedSources := "none"
	if len(sources) > 0 {
		resolvedSources = strings.Join(sources, " · ")
	}
	return strings.TrimSpace(mode) + " | fields: " + resolvedFields + " | sources: " + resolvedSources
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		trimmed := strings.TrimSpace(value)
		if trimmed != "" {
			return trimmed
		}
	}
	return ""
}

func trimPrefix(value string, max int) string {
	if max <= 0 || len(value) <= max {
		return value
	}
	return value[:max]
}

func fallbackText(value string, fallback string) string {
	if strings.TrimSpace(value) == "" {
		return fallback
	}
	return value
}

func asMap(value any) map[string]any {
	if value == nil {
		return map[string]any{}
	}
	if typed, ok := value.(map[string]any); ok {
		return typed
	}
	if typed, ok := value.(map[string]interface{}); ok {
		return typed
	}
	return map[string]any{}
}

func stringValue(value any) string {
	if value == nil {
		return ""
	}
	switch typed := value.(type) {
	case string:
		return typed
	default:
		return fmt.Sprint(typed)
	}
}

func boolValue(value any) bool {
	switch typed := value.(type) {
	case bool:
		return typed
	case float64:
		return typed != 0
	case int:
		return typed != 0
	case string:
		trimmed := strings.ToLower(strings.TrimSpace(typed))
		return trimmed == "true" || trimmed == "1" || trimmed == "yes"
	default:
		return false
	}
}

func intValue(value any) int {
	switch typed := value.(type) {
	case int:
		return typed
	case int64:
		return int(typed)
	case float64:
		return int(typed)
	case json.Number:
		resolved, _ := typed.Int64()
		return int(resolved)
	case string:
		var parsed int
		_, _ = fmt.Sscanf(strings.TrimSpace(typed), "%d", &parsed)
		return parsed
	default:
		return 0
	}
}

func stringSlice(value any) []string {
	list, ok := value.([]any)
	if !ok {
		if typed, ok := value.([]string); ok {
			return append([]string(nil), typed...)
		}
		return nil
	}
	result := make([]string, 0, len(list))
	for _, item := range list {
		text := strings.TrimSpace(stringValue(item))
		if text == "" {
			continue
		}
		result = append(result, text)
	}
	return result
}

func decodeBase64URL(value string) ([]byte, error) {
	normalized := strings.ReplaceAll(value, "-", "+")
	normalized = strings.ReplaceAll(normalized, "_", "/")
	switch len(normalized) % 4 {
	case 2:
		normalized += "=="
	case 3:
		normalized += "="
	}
	return base64.StdEncoding.DecodeString(normalized)
}

func encodeBase64URL(value []byte) string {
	return strings.TrimRight(base64.URLEncoding.EncodeToString(value), "=")
}
