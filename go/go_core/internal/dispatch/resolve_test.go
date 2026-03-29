package dispatch

import "testing"

func TestResolvePrefersRequestedProviderWhenCapabilitiesMatch(t *testing.T) {
	result := Resolve(Request{
		Providers: []Provider{
			{
				ID:           "codex",
				Name:         "Codex",
				Capabilities: []string{"chat", "gateway-bridge"},
			},
			{
				ID:           "qwen",
				Name:         "Qwen",
				Capabilities: []string{"chat"},
			},
		},
		PreferredProviderID:  "codex",
		RequiredCapabilities: []string{"gateway-bridge"},
	})

	if result.Provider == nil || result.Provider.ID != "codex" {
		t.Fatalf("expected codex provider, got %#v", result.Provider)
	}
}

func TestResolveFallsBackDeterministicallyByID(t *testing.T) {
	result := Resolve(Request{
		Providers: []Provider{
			{
				ID:           "qwen",
				Name:         "Qwen",
				Capabilities: []string{"chat"},
			},
			{
				ID:           "codex",
				Name:         "Codex",
				Capabilities: []string{"chat"},
			},
		},
		RequiredCapabilities: []string{"chat"},
	})

	if result.Provider == nil || result.Provider.ID != "codex" {
		t.Fatalf("expected deterministic codex fallback, got %#v", result.Provider)
	}
}

func TestResolveBuildsGatewayDispatchMetadata(t *testing.T) {
	result := Resolve(Request{
		Providers: []Provider{
			{
				ID:           "codex",
				Name:         "Codex CLI",
				DefaultArgs:  []string{"app-server"},
				Capabilities: []string{"chat", "gateway-bridge"},
			},
		},
		PreferredProviderID:  "codex",
		RequiredCapabilities: []string{"gateway-bridge"},
		NodeState: &NodeState{
			SelectedAgentID:      "main",
			GatewayConnected:     true,
			ExecutionTarget:      "local",
			RuntimeMode:          "externalCli",
			BridgeEnabled:        true,
			BridgeState:          "registered",
			ResolvedCodexCLIPath: "/opt/homebrew/bin/codex",
		},
		NodeInfo: &NodeInfo{
			ID:      "xworkmate-app",
			Name:    "XWorkmate",
			Version: "1.0.0",
		},
	})

	if result.Provider == nil || result.Provider.ID != "codex" {
		t.Fatalf("expected codex provider, got %#v", result.Provider)
	}
	if result.AgentID != "main" {
		t.Fatalf("expected agent id main, got %q", result.AgentID)
	}
	dispatch, ok := result.Metadata["dispatch"].(map[string]any)
	if !ok || dispatch["mode"] != "cooperative" {
		t.Fatalf("expected cooperative dispatch, got %#v", result.Metadata["dispatch"])
	}
	bridge, ok := result.Metadata["bridge"].(map[string]any)
	if !ok || bridge["localTransport"] != "stdio-jsonrpc" {
		t.Fatalf("expected stdio-jsonrpc bridge transport, got %#v", result.Metadata["bridge"])
	}
	provider, ok := result.Metadata["provider"].(map[string]any)
	if !ok || provider["id"] != "codex" {
		t.Fatalf("expected provider metadata for codex, got %#v", result.Metadata["provider"])
	}
}
