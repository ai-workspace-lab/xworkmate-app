package dispatch

import (
	"maps"
	"slices"
	"strings"
)

type Provider struct {
	ID           string
	Name         string
	DefaultArgs  []string
	Capabilities []string
}

type NodeState struct {
	SelectedAgentID        string
	GatewayConnected       bool
	ExecutionTarget        string
	RuntimeMode            string
	BridgeEnabled          bool
	BridgeState            string
	ResolvedCodexCLIPath   string
	ConfiguredCodexCLIPath string
}

type NodeInfo struct {
	ID      string
	Name    string
	Version string
}

type Request struct {
	Providers            []Provider
	PreferredProviderID  string
	RequiredCapabilities []string
	NodeState            *NodeState
	NodeInfo             *NodeInfo
}

type Result struct {
	Provider *Provider
	AgentID  string
	Metadata map[string]any
}

func Resolve(request Request) Result {
	provider := selectProvider(
		request.Providers,
		request.PreferredProviderID,
		request.RequiredCapabilities,
	)
	if request.NodeState == nil {
		return Result{Provider: provider, Metadata: map[string]any{}}
	}

	state := request.NodeState
	nodeInfo := request.NodeInfo
	nodeID := "xworkmate-app"
	nodeName := "XWorkmate"
	nodeVersion := ""
	if nodeInfo != nil {
		if strings.TrimSpace(nodeInfo.ID) != "" {
			nodeID = strings.TrimSpace(nodeInfo.ID)
		}
		if strings.TrimSpace(nodeInfo.Name) != "" {
			nodeName = strings.TrimSpace(nodeInfo.Name)
		}
		nodeVersion = strings.TrimSpace(nodeInfo.Version)
	}

	configuredPath := strings.TrimSpace(state.ConfiguredCodexCLIPath)
	if strings.TrimSpace(state.ResolvedCodexCLIPath) != "" {
		configuredPath = strings.TrimSpace(state.ResolvedCodexCLIPath)
	}
	localTransport := "stdio-jsonrpc"
	if strings.TrimSpace(state.RuntimeMode) == "builtIn" {
		localTransport = "ffi-runtime"
	}

	metadata := map[string]any{
		"node": map[string]any{
			"id":               nodeID,
			"name":             nodeName,
			"version":          nodeVersion,
			"kind":             "app-mediated-cooperative-node",
			"gatewayTransport": "websocket-rpc",
		},
		"dispatch": map[string]any{
			"mode":            dispatchMode(state.BridgeEnabled),
			"executionTarget": strings.TrimSpace(state.ExecutionTarget),
		},
		"bridge": map[string]any{
			"enabled":          state.BridgeEnabled,
			"state":            strings.TrimSpace(state.BridgeState),
			"gatewayConnected": state.GatewayConnected,
			"runtimeMode":      strings.TrimSpace(state.RuntimeMode),
			"localTransport":   localTransport,
		},
	}
	if configuredPath != "" {
		bridge := metadata["bridge"].(map[string]any)
		bridge["binaryConfigured"] = true
	}
	if provider != nil {
		metadata["provider"] = map[string]any{
			"id":           provider.ID,
			"name":         provider.Name,
			"defaultArgs":  provider.DefaultArgs,
			"capabilities": provider.Capabilities,
		}
	}

	return Result{
		Provider: provider,
		AgentID:  strings.TrimSpace(state.SelectedAgentID),
		Metadata: metadata,
	}
}

func dispatchMode(bridgeEnabled bool) string {
	if bridgeEnabled {
		return "cooperative"
	}
	return "gateway-only"
}

func selectProvider(
	providers []Provider,
	preferredProviderID string,
	requiredCapabilities []string,
) *Provider {
	required := normalizeCapabilities(requiredCapabilities)
	preferredID := strings.TrimSpace(preferredProviderID)
	if preferredID != "" {
		for _, provider := range providers {
			if provider.ID == preferredID && supportsProvider(provider, required) {
				candidate := provider
				return &candidate
			}
		}
	}

	filtered := make([]Provider, 0, len(providers))
	for _, provider := range providers {
		if supportsProvider(provider, required) {
			filtered = append(filtered, provider)
		}
	}
	if len(filtered) == 0 {
		return nil
	}
	slices.SortFunc(filtered, func(a, b Provider) int {
		return strings.Compare(a.ID, b.ID)
	})
	candidate := filtered[0]
	return &candidate
}

func supportsProvider(provider Provider, required map[string]struct{}) bool {
	if len(required) == 0 {
		return true
	}
	provided := normalizeCapabilities(provider.Capabilities)
	for capability := range required {
		if _, ok := provided[capability]; !ok {
			return false
		}
	}
	return true
}

func normalizeCapabilities(values []string) map[string]struct{} {
	normalized := map[string]struct{}{}
	for _, value := range values {
		item := strings.TrimSpace(strings.ToLower(value))
		if item == "" {
			continue
		}
		normalized[item] = struct{}{}
	}
	return normalized
}

func ResultMap(result Result) map[string]any {
	response := map[string]any{
		"metadata": result.Metadata,
	}
	if result.Provider != nil {
		provider := *result.Provider
		response["providerId"] = provider.ID
		response["provider"] = map[string]any{
			"id":           provider.ID,
			"name":         provider.Name,
			"defaultArgs":  slices.Clone(provider.DefaultArgs),
			"capabilities": slices.Clone(provider.Capabilities),
		}
	}
	if strings.TrimSpace(result.AgentID) != "" {
		response["agentId"] = strings.TrimSpace(result.AgentID)
	}
	return maps.Clone(response)
}
