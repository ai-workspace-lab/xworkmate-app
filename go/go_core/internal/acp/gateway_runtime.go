package acp

import (
	"strings"
	"time"

	"xworkmate/go_core/internal/gatewayruntime"
	"xworkmate/go_core/internal/shared"
)

func handleGatewayConnect(
	server *Server,
	params map[string]any,
	notify func(map[string]any),
) map[string]any {
	request := gatewayruntime.ConnectRequest{
		RuntimeID:          strings.TrimSpace(shared.StringArg(params, "runtimeId", "")),
		Mode:               strings.TrimSpace(shared.StringArg(params, "mode", "unconfigured")),
		ClientID:           strings.TrimSpace(shared.StringArg(params, "clientId", "")),
		Locale:             strings.TrimSpace(shared.StringArg(params, "locale", "")),
		UserAgent:          strings.TrimSpace(shared.StringArg(params, "userAgent", "")),
		ConnectAuthMode:    strings.TrimSpace(shared.StringArg(params, "connectAuthMode", "")),
		ConnectAuthFields:  parseGatewayRuntimeStringSlice(params["connectAuthFields"]),
		ConnectAuthSources: parseGatewayRuntimeStringSlice(params["connectAuthSources"]),
		HasSharedAuth:      parseBool(params["hasSharedAuth"]),
		HasDeviceToken:     parseBool(params["hasDeviceToken"]),
		Endpoint: gatewayruntime.Endpoint{
			Host: strings.TrimSpace(shared.StringArg(asMap(params["endpoint"]), "host", "")),
			Port: parsePositiveInt(asMap(params["endpoint"])["port"]),
			TLS:  parseBool(asMap(params["endpoint"])["tls"]),
		},
		PackageInfo: gatewayruntime.PackageInfo{
			AppName:     strings.TrimSpace(shared.StringArg(asMap(params["packageInfo"]), "appName", "")),
			PackageName: strings.TrimSpace(shared.StringArg(asMap(params["packageInfo"]), "packageName", "")),
			Version:     strings.TrimSpace(shared.StringArg(asMap(params["packageInfo"]), "version", "")),
			BuildNumber: strings.TrimSpace(shared.StringArg(asMap(params["packageInfo"]), "buildNumber", "")),
		},
		DeviceInfo: gatewayruntime.DeviceInfo{
			Platform:        strings.TrimSpace(shared.StringArg(asMap(params["deviceInfo"]), "platform", "")),
			PlatformVersion: strings.TrimSpace(shared.StringArg(asMap(params["deviceInfo"]), "platformVersion", "")),
			DeviceFamily:    strings.TrimSpace(shared.StringArg(asMap(params["deviceInfo"]), "deviceFamily", "")),
			ModelIdentifier: strings.TrimSpace(shared.StringArg(asMap(params["deviceInfo"]), "modelIdentifier", "")),
		},
		Identity: gatewayruntime.DeviceIdentity{
			DeviceID:            strings.TrimSpace(shared.StringArg(asMap(params["identity"]), "deviceId", "")),
			PublicKeyBase64URL:  strings.TrimSpace(shared.StringArg(asMap(params["identity"]), "publicKeyBase64Url", "")),
			PrivateKeyBase64URL: strings.TrimSpace(shared.StringArg(asMap(params["identity"]), "privateKeyBase64Url", "")),
		},
		Auth: gatewayruntime.AuthConfig{
			Token:       strings.TrimSpace(shared.StringArg(asMap(params["auth"]), "token", "")),
			DeviceToken: strings.TrimSpace(shared.StringArg(asMap(params["auth"]), "deviceToken", "")),
			Password:    strings.TrimSpace(shared.StringArg(asMap(params["auth"]), "password", "")),
		},
	}
	result := server.gateway.Connect(request, notify)
	return map[string]any{
		"ok":                  result.OK,
		"snapshot":            result.Snapshot,
		"auth":                result.Auth,
		"returnedDeviceToken": result.ReturnedDeviceToken,
		"error":               result.Error,
	}
}

func handleGatewayRequest(
	server *Server,
	params map[string]any,
	notify func(map[string]any),
) map[string]any {
	timeout := time.Duration(parsePositiveInt(params["timeoutMs"])) * time.Millisecond
	result := server.gateway.Request(
		strings.TrimSpace(shared.StringArg(params, "runtimeId", "")),
		strings.TrimSpace(shared.StringArg(params, "method", "")),
		asMap(params["params"]),
		timeout,
		notify,
	)
	return map[string]any{
		"ok":      result.OK,
		"payload": result.Payload,
		"error":   result.Error,
	}
}

func handleGatewayDisconnect(
	server *Server,
	params map[string]any,
	notify func(map[string]any),
) map[string]any {
	server.gateway.Disconnect(
		strings.TrimSpace(shared.StringArg(params, "runtimeId", "")),
		notify,
	)
	return map[string]any{"accepted": true}
}

func asMap(value any) map[string]any {
	if typed, ok := value.(map[string]any); ok {
		return typed
	}
	if typed, ok := value.(map[string]interface{}); ok {
		return typed
	}
	return map[string]any{}
}

func parseGatewayRuntimeStringSlice(value any) []string {
	list, ok := value.([]any)
	if !ok {
		if typed, ok := value.([]string); ok {
			return append([]string(nil), typed...)
		}
		return nil
	}
	result := make([]string, 0, len(list))
	for _, item := range list {
		text := strings.TrimSpace(shared.StringArg(map[string]any{"value": item}, "value", ""))
		if text == "" {
			continue
		}
		result = append(result, text)
	}
	return result
}

func parseBool(value any) bool {
	switch typed := value.(type) {
	case bool:
		return typed
	case string:
		return shared.BoolArg(typed, false)
	case float64:
		return typed != 0
	case int:
		return typed != 0
	default:
		return false
	}
}

func parsePositiveInt(value any) int {
	switch typed := value.(type) {
	case int:
		if typed > 0 {
			return typed
		}
	case int64:
		if typed > 0 {
			return int(typed)
		}
	case float64:
		if typed > 0 {
			return int(typed)
		}
	case string:
		return shared.IntArg(typed, 0)
	}
	return 0
}
