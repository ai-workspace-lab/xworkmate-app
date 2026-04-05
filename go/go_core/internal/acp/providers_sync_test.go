package acp

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"

	"xworkmate/go_core/internal/shared"
)

func TestCapabilitiesIgnoreLocalProviderAutodetectUntilSync(t *testing.T) {
	fakeProvider := t.TempDir() + "/fake-claude"
	if err := os.WriteFile(fakeProvider, []byte("#!/bin/sh\nexit 0\n"), 0o755); err != nil {
		t.Fatalf("write fake provider: %v", err)
	}
	t.Setenv("ACP_CLAUDE_BIN", fakeProvider)

	server := NewServer()
	result, rpcErr := server.handleRequest(shared.RPCRequest{
		Method: "acp.capabilities",
		Params: map[string]any{},
	}, func(map[string]any) {})
	if rpcErr != nil {
		t.Fatalf("expected capabilities success, got %v", rpcErr)
	}

	providers, _ := result["providers"].([]string)
	if len(providers) != 0 {
		t.Fatalf("expected no providers before sync, got %#v", providers)
	}
}

func TestProvidersSyncUpdatesCapabilities(t *testing.T) {
	server := NewServer()

	_, rpcErr := server.handleRequest(shared.RPCRequest{
		Method: "xworkmate.providers.sync",
		Params: map[string]any{
			"providers": []any{
				map[string]any{
					"providerId":          "claude",
					"label":               "Claude",
					"endpoint":            "http://127.0.0.1:9999",
					"authorizationHeader": "Bearer test",
					"enabled":             true,
				},
			},
		},
	}, func(map[string]any) {})
	if rpcErr != nil {
		t.Fatalf("expected sync success, got %v", rpcErr)
	}

	result, rpcErr := server.handleRequest(shared.RPCRequest{
		Method: "acp.capabilities",
		Params: map[string]any{},
	}, func(map[string]any) {})
	if rpcErr != nil {
		t.Fatalf("expected capabilities success, got %v", rpcErr)
	}
	providers, _ := result["providers"].([]string)
	if len(providers) == 0 {
		t.Fatalf("expected synced provider in capabilities, got %#v", result)
	}
	found := false
	for _, provider := range providers {
		if provider == "claude" {
			found = true
			break
		}
	}
	if !found {
		t.Fatalf("expected claude provider after sync, got %#v", providers)
	}
}

func TestExecuteSessionTaskUsesSyncedExternalProvider(t *testing.T) {
	externalServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/acp/rpc" {
			http.NotFound(w, r)
			return
		}
		defer r.Body.Close()
		var request map[string]any
		if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
			t.Fatalf("decode request: %v", err)
		}
		method, _ := request["method"].(string)
		switch method {
		case "session.start":
			_ = json.NewEncoder(w).Encode(map[string]any{
				"jsonrpc": "2.0",
				"id":      request["id"],
				"result": map[string]any{
					"success":  true,
					"output":   "external-provider-ok",
					"turnId":   "turn-external",
					"provider": "claude",
					"mode":     "single-agent",
				},
			})
		default:
			_ = json.NewEncoder(w).Encode(map[string]any{
				"jsonrpc": "2.0",
				"id":      request["id"],
				"result":  map[string]any{"ok": true},
			})
		}
	}))
	defer externalServer.Close()

	server := NewServer()
	server.syncProviders([]syncedProvider{
		{
			ProviderID:          "claude",
			Label:               "Claude",
			Endpoint:            externalServer.URL,
			AuthorizationHeader: "Bearer test",
			Enabled:             true,
		},
	})

	response, rpcErr := server.executeSessionTask(task{
		req: shared.RPCRequest{
			Method: "session.start",
			Params: map[string]any{
				"sessionId":        "session-external",
				"threadId":         "thread-external",
				"taskPrompt":       "hello from external provider",
				"workingDirectory": t.TempDir(),
				"routing": map[string]any{
					"routingMode":             "explicit",
					"explicitExecutionTarget": "singleAgent",
					"explicitProviderId":      "claude",
				},
			},
		},
	})
	if rpcErr != nil {
		t.Fatalf("expected success, got rpc error: %v", rpcErr)
	}
	if got := response["output"]; got != "external-provider-ok" {
		t.Fatalf("expected external provider output, got %#v", response)
	}
	if got := response["resolvedProviderId"]; got != "claude" {
		t.Fatalf("expected resolved provider claude, got %#v", response)
	}
}
