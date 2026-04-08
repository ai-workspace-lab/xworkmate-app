package acp

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/gorilla/websocket"

	"xworkmate/go_core/internal/router"
	"xworkmate/go_core/internal/shared"
)

const (
	externalProviderEndpointKey            = "externalProviderEndpoint"
	externalProviderAuthorizationHeaderKey = "externalProviderAuthorizationHeader"
	externalProviderLabelKey               = "externalProviderLabel"
)

func buildResolvedExecutionParams(
	params map[string]any,
	resolved router.Result,
) map[string]any {
	next := make(map[string]any, len(params)+8)
	for key, value := range params {
		next[key] = value
	}
	switch resolved.ResolvedExecutionTarget {
	case router.ExecutionTargetGateway:
		next["mode"] = router.ExecutionTargetGatewayChat
		next["executionTarget"] = resolved.ResolvedEndpointTarget
	case router.ExecutionTargetMultiAgent:
		next["mode"] = router.ExecutionTargetMultiAgent
	default:
		next["mode"] = router.ExecutionTargetSingleAgent
	}
	if strings.TrimSpace(resolved.ResolvedProviderID) != "" {
		next["provider"] = strings.TrimSpace(resolved.ResolvedProviderID)
	}
	if strings.TrimSpace(resolved.ResolvedModel) != "" {
		next["model"] = strings.TrimSpace(resolved.ResolvedModel)
	}
	if len(resolved.ResolvedSkills) > 0 {
		next["selectedSkills"] = append([]string(nil), resolved.ResolvedSkills...)
	}
	next["resolvedExecutionTarget"] = resolved.ResolvedExecutionTarget
	next["resolvedEndpointTarget"] = resolved.ResolvedEndpointTarget
	next["resolvedProviderId"] = resolved.ResolvedProviderID
	next["resolvedModel"] = resolved.ResolvedModel
	next["resolvedSkills"] = append([]string(nil), resolved.ResolvedSkills...)
	return next
}

func injectResolvedExternalProviderParams(
	params map[string]any,
	provider syncedProvider,
) map[string]any {
	if params == nil {
		params = map[string]any{}
	}
	if endpoint := strings.TrimSpace(provider.Endpoint); endpoint != "" {
		params[externalProviderEndpointKey] = endpoint
	}
	if authorization := strings.TrimSpace(provider.AuthorizationHeader); authorization != "" {
		params[externalProviderAuthorizationHeaderKey] = authorization
	}
	if label := strings.TrimSpace(provider.Label); label != "" {
		params[externalProviderLabelKey] = label
	}
	return params
}

func (s *Server) runGateway(
	ctx context.Context,
	method string,
	session *session,
	params map[string]any,
	turnID string,
	notify func(map[string]any),
) taskResult {
	_ = ctx
	executionTarget := strings.TrimSpace(shared.StringArg(params, "executionTarget", ""))
	if executionTarget == "" {
		executionTarget = router.EndpointTargetLocal
	}
	result := s.gateway.RequestByMode(
		executionTarget,
		method,
		params,
		2*time.Minute,
		notify,
	)
	if !result.OK {
		errMessage := strings.TrimSpace(shared.StringArg(result.Error, "message", "gateway execution failed"))
		s.emitSessionUpdate(session, notify, turnID, map[string]any{
			"type":    "status",
			"event":   "completed",
			"message": errMessage,
			"pending": false,
			"error":   true,
		})
		return taskResult{
			response: map[string]any{
				"success": false,
				"error":   errMessage,
				"turnId":  turnID,
				"mode":    router.ExecutionTargetGatewayChat,
			},
		}
	}
	payload := asMap(result.Payload)
	if len(payload) == 0 {
		payload = map[string]any{
			"success": true,
			"turnId":  turnID,
			"mode":    router.ExecutionTargetGatewayChat,
		}
	}
	if _, ok := payload["turnId"]; !ok {
		payload["turnId"] = turnID
	}
	if _, ok := payload["mode"]; !ok {
		payload["mode"] = router.ExecutionTargetGatewayChat
	}
	return taskResult{response: payload}
}

func (s *Server) runSingleAgentViaExternalProvider(
	ctx context.Context,
	provider syncedProvider,
	method string,
	params map[string]any,
	notify func(map[string]any),
) (map[string]any, error) {
	endpoint := strings.TrimSpace(provider.Endpoint)
	if endpoint == "" {
		return nil, fmt.Errorf("external provider endpoint is missing")
	}
	forwardParams := sanitizeExternalACPParams(method, params)
	return requestExternalACP(
		ctx,
		endpoint,
		provider.AuthorizationHeader,
		method,
		forwardParams,
		notify,
	)
}

func sanitizeExternalACPParams(method string, params map[string]any) map[string]any {
	if len(params) == 0 {
		return map[string]any{}
	}
	next := make(map[string]any, len(params))
	for key, value := range params {
		next[key] = value
	}
	// Internal routing/runtime fields must not leak into external provider payloads.
	delete(next, "metadata")
	delete(next, "resolvedExecutionTarget")
	delete(next, "resolvedEndpointTarget")
	delete(next, "resolvedProviderId")
	delete(next, "resolvedModel")
	delete(next, "resolvedSkills")
	delete(next, externalProviderEndpointKey)
	delete(next, externalProviderAuthorizationHeaderKey)
	delete(next, externalProviderLabelKey)
	// Gateway-only fields are irrelevant in ACP single-agent forwarding.
	normalizedMethod := strings.TrimSpace(method)
	if normalizedMethod == "session.start" || normalizedMethod == "session.message" {
		delete(next, "executionTarget")
		delete(next, "agentId")
	}
	return next
}

func externalProviderFromParams(params map[string]any) (syncedProvider, bool) {
	endpoint := strings.TrimSpace(shared.StringArg(params, externalProviderEndpointKey, ""))
	if endpoint == "" {
		return syncedProvider{}, false
	}
	return syncedProvider{
		ProviderID:          strings.TrimSpace(shared.StringArg(params, "provider", "")),
		Label:               strings.TrimSpace(shared.StringArg(params, externalProviderLabelKey, "")),
		Endpoint:            endpoint,
		AuthorizationHeader: strings.TrimSpace(shared.StringArg(params, externalProviderAuthorizationHeaderKey, "")),
		Enabled:             true,
	}, true
}

func requestExternalACP(
	ctx context.Context,
	endpoint,
	authorization,
	method string,
	params map[string]any,
	notify func(map[string]any),
) (map[string]any, error) {
	parsed, err := httpOrWebsocketEndpoint(endpoint)
	if err != nil {
		return nil, err
	}
	switch parsed.Scheme {
	case "http", "https":
		return requestExternalACPHTTP(ctx, parsed, authorization, method, params)
	default:
		return requestExternalACPWebSocket(ctx, parsed, authorization, method, params, notify)
	}
}

func requestExternalACPHTTP(
	ctx context.Context,
	endpoint *urlSpec,
	authorization,
	method string,
	params map[string]any,
) (map[string]any, error) {
	requestBody, _ := json.Marshal(map[string]any{
		"jsonrpc": "2.0",
		"id":      fmt.Sprintf("req-%d", time.Now().UnixNano()),
		"method":  method,
		"params":  params,
	})
	req, err := http.NewRequestWithContext(
		ctx,
		http.MethodPost,
		endpoint.httpRPCEndpoint(),
		strings.NewReader(string(requestBody)),
	)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json; charset=utf-8")
	req.Header.Set("Accept", "application/json")
	if strings.TrimSpace(authorization) != "" {
		req.Header.Set("Authorization", strings.TrimSpace(authorization))
	}
	response, err := (&http.Client{Timeout: 2 * time.Minute}).Do(req)
	if err != nil {
		return nil, err
	}
	defer response.Body.Close()
	var decoded map[string]any
	if err := json.NewDecoder(response.Body).Decode(&decoded); err != nil {
		return nil, err
	}
	if errPayload := asMap(decoded["error"]); len(errPayload) > 0 {
		return nil, fmt.Errorf(
			"%s",
			strings.TrimSpace(shared.StringArg(errPayload, "message", "external ACP request failed")),
		)
	}
	return decoded, nil
}

func requestExternalACPWebSocket(
	ctx context.Context,
	endpoint *urlSpec,
	authorization,
	method string,
	params map[string]any,
	notify func(map[string]any),
) (map[string]any, error) {
	headers := http.Header{}
	if strings.TrimSpace(authorization) != "" {
		headers.Set("Authorization", strings.TrimSpace(authorization))
	}
	conn, _, err := websocket.DefaultDialer.DialContext(
		ctx,
		endpoint.webSocketEndpoint(),
		headers,
	)
	if err != nil {
		return nil, err
	}
	defer conn.Close()

	requestID := fmt.Sprintf("req-%d", time.Now().UnixNano())
	if err := conn.WriteJSON(map[string]any{
		"jsonrpc": "2.0",
		"id":      requestID,
		"method":  method,
		"params":  params,
	}); err != nil {
		return nil, err
	}

	for {
		if err := conn.SetReadDeadline(time.Now().Add(2 * time.Minute)); err != nil {
			return nil, err
		}
		var payload map[string]any
		if err := conn.ReadJSON(&payload); err != nil {
			return nil, err
		}
		if strings.TrimSpace(shared.StringArg(payload, "id", "")) == requestID &&
			(payload["result"] != nil || payload["error"] != nil) {
			if errPayload := asMap(payload["error"]); len(errPayload) > 0 {
				return nil, fmt.Errorf(
					"%s",
					strings.TrimSpace(shared.StringArg(errPayload, "message", "external ACP request failed")),
				)
			}
			return payload, nil
		}
		if notify != nil && strings.TrimSpace(shared.StringArg(payload, "method", "")) != "" {
			notify(payload)
		}
	}
}

type urlSpec struct {
	Scheme string
	Host   string
	Port   string
	Path   string
}

func httpOrWebsocketEndpoint(raw string) (*urlSpec, error) {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		return nil, fmt.Errorf("missing external ACP endpoint")
	}
	parsed, err := url.ParseRequestURI(trimmed)
	if err != nil {
		return nil, err
	}
	scheme := strings.ToLower(strings.TrimSpace(parsed.Scheme))
	if scheme != "http" && scheme != "https" && scheme != "ws" && scheme != "wss" {
		return nil, fmt.Errorf("unsupported external ACP scheme: %s", scheme)
	}
	return &urlSpec{
		Scheme: scheme,
		Host:   parsed.Host,
		Path:   strings.TrimRight(parsed.Path, "/"),
	}, nil
}

func (u *urlSpec) basePath() string {
	path := strings.TrimSpace(u.Path)
	if path == "" || path == "/" {
		return ""
	}
	if strings.HasSuffix(path, "/acp/rpc") {
		path = strings.TrimSuffix(path, "/acp/rpc")
	} else if strings.HasSuffix(path, "/acp") {
		path = strings.TrimSuffix(path, "/acp")
	}
	path = strings.TrimRight(path, "/")
	if path == "" || path == "/" {
		return ""
	}
	if !strings.HasPrefix(path, "/") {
		return "/" + path
	}
	return path
}

func (u *urlSpec) httpRPCEndpoint() string {
	scheme := u.Scheme
	if scheme == "ws" {
		scheme = "http"
	} else if scheme == "wss" {
		scheme = "https"
	}
	basePath := u.basePath()
	if basePath == "" {
		basePath = "/acp/rpc"
	} else {
		basePath += "/acp/rpc"
	}
	return fmt.Sprintf("%s://%s%s", scheme, u.Host, basePath)
}

func (u *urlSpec) webSocketEndpoint() string {
	scheme := u.Scheme
	if scheme == "http" {
		scheme = "ws"
	} else if scheme == "https" {
		scheme = "wss"
	}
	basePath := u.basePath()
	if basePath == "" {
		basePath = "/acp"
	} else {
		basePath += "/acp"
	}
	return fmt.Sprintf("%s://%s%s", scheme, u.Host, basePath)
}
