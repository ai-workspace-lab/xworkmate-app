package mounts

import (
	"context"
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"
)

type ManagedMCPServer struct {
	ID        string
	Name      string
	Transport string
	Command   string
	URL       string
	Args      []string
	Enabled   bool
}

type Config struct {
	AutoSync          bool
	UsesAris          bool
	ManagedMCPServers []ManagedMCPServer
}

type ArisInput struct {
	Available         bool
	BundleVersion     string
	LLMChatServerPath string
	SkillCount        int
	BridgeAvailable   bool
	Error             string
}

type Request struct {
	Config                 Config
	AIGatewayURL           string
	ConfiguredCodexCLIPath string
	CodexHome              string
	OpencodeHome           string
	OpenClawHome           string
	Aris                   ArisInput
}

type MountTargetState struct {
	TargetID                   string
	Label                      string
	Available                  bool
	SupportsSkills             bool
	SupportsMCP                bool
	SupportsAIGatewayInjection bool
	DiscoveryState             string
	SyncState                  string
	DiscoveredSkillCount       int
	DiscoveredMCPCount         int
	ManagedMCPCount            int
	Detail                     string
}

type Result struct {
	MountTargets      []MountTargetState
	ArisBundleVersion string
	ArisCompatStatus  string
}

func Reconcile(request Request) Result {
	states := []MountTargetState{
		reconcileAris(request.Config, request.Aris),
		reconcileCodex(
			request.Config,
			request.AIGatewayURL,
			request.ConfiguredCodexCLIPath,
			request.CodexHome,
		),
		reconcileCLIListTarget(
			request.Config,
			"claude",
			"Claude",
			[]string{"claude", "mcp", "list"},
		),
		reconcileCLIListTarget(
			request.Config,
			"gemini",
			"Gemini",
			[]string{"gemini", "mcp", "list"},
		),
		reconcileOpencode(request.Config, request.OpencodeHome),
		reconcileOpenClaw(request.Config, request.OpenClawHome),
	}

	result := Result{
		MountTargets:      states,
		ArisBundleVersion: strings.TrimSpace(request.Aris.BundleVersion),
		ArisCompatStatus:  "idle",
	}
	for _, state := range states {
		if state.TargetID == "aris" {
			result.ArisCompatStatus = state.SyncState
			break
		}
	}
	return result
}

func ResultMap(result Result) map[string]any {
	rawTargets := make([]map[string]any, 0, len(result.MountTargets))
	for _, target := range result.MountTargets {
		rawTargets = append(rawTargets, map[string]any{
			"targetId":                   target.TargetID,
			"label":                      target.Label,
			"available":                  target.Available,
			"supportsSkills":             target.SupportsSkills,
			"supportsMcp":                target.SupportsMCP,
			"supportsAiGatewayInjection": target.SupportsAIGatewayInjection,
			"discoveryState":             target.DiscoveryState,
			"syncState":                  target.SyncState,
			"discoveredSkillCount":       target.DiscoveredSkillCount,
			"discoveredMcpCount":         target.DiscoveredMCPCount,
			"managedMcpCount":            target.ManagedMCPCount,
			"detail":                     target.Detail,
		})
	}
	return map[string]any{
		"mountTargets":      rawTargets,
		"arisBundleVersion": result.ArisBundleVersion,
		"arisCompatStatus":  result.ArisCompatStatus,
	}
}

func reconcileAris(config Config, input ArisInput) MountTargetState {
	state := placeholderState("aris", "ARIS", true, true, false)
	if strings.TrimSpace(input.Error) != "" {
		state.Available = false
		state.DiscoveryState = "error"
		state.SyncState = "error"
		state.Detail = strings.TrimSpace(input.Error)
		return state
	}
	if !input.Available {
		state.DiscoveryState = "missing"
		state.SyncState = "missing"
		state.Detail = "Embedded ARIS bundle is unavailable."
		return state
	}

	state.Available = true
	state.DiscoveryState = "ready"
	state.DiscoveredSkillCount = input.SkillCount
	llmChatReady := strings.TrimSpace(input.LLMChatServerPath) != ""
	if config.UsesAris && llmChatReady && input.BridgeAvailable {
		state.SyncState = "ready"
		state.DiscoveredMCPCount = 1
		state.ManagedMCPCount = 1
		state.Detail = "Embedded bundle " +
			strings.TrimSpace(input.BundleVersion) +
			" ready; XWorkmate Go core manages llm-chat and claude-review."
		return state
	}
	state.SyncState = "embedded"
	if llmChatReady {
		state.DiscoveredMCPCount = 1
	}
	if llmChatReady {
		state.Detail = "Embedded bundle extracted, but the XWorkmate Go core is not available yet."
	} else {
		state.Detail = "Embedded bundle extracted, but llm-chat metadata is missing."
	}
	return state
}

func reconcileCodex(
	config Config,
	aiGatewayURL string,
	configuredCodexCLIPath string,
	codexHome string,
) MountTargetState {
	state := placeholderState("codex", "Codex", true, true, true)
	available := codexAvailable(configuredCodexCLIPath)
	configHome := strings.TrimSpace(codexHome)
	if configHome == "" {
		configHome = defaultCodexHome()
	}
	configPath := filepath.Join(configHome, "config.toml")
	content, _ := os.ReadFile(configPath)
	discovered := countMCPSections(string(content))
	managedServers := enabledCodexServers(config.ManagedMCPServers)
	if available && config.AutoSync && len(managedServers) > 0 {
		_ = applyManagedBlock(
			configPath,
			buildCodexManagedMCPBlock(managedServers),
			codexManagedMCPBlockStart,
			codexManagedMCPBlockEnd,
		)
	}
	state.Available = available
	if available {
		state.DiscoveryState = "ready"
	} else {
		state.DiscoveryState = "missing"
	}
	switch {
	case !available:
		state.SyncState = "missing"
	case config.AutoSync:
		state.SyncState = "ready"
	default:
		state.SyncState = "disabled"
	}
	state.DiscoveredMCPCount = discovered
	state.ManagedMCPCount = len(managedServers)
	if strings.TrimSpace(aiGatewayURL) != "" {
		state.Detail = "LLM API uses launch-scoped defaults for collaboration runs."
	} else {
		state.Detail = "LLM API not configured."
	}
	return state
}

func reconcileCLIListTarget(
	config Config,
	targetID string,
	label string,
	command []string,
) MountTargetState {
	state := placeholderState(targetID, label, true, true, true)
	available := binaryExists(command[0])
	discovered := 0
	if available {
		discovered = countListedEntries(command)
	}
	state.Available = available
	if available {
		state.DiscoveryState = "ready"
	} else {
		state.DiscoveryState = "missing"
	}
	if available && config.AutoSync {
		state.SyncState = "launch-only"
	} else {
		state.SyncState = "disabled"
	}
	state.DiscoveredMCPCount = discovered
	state.ManagedMCPCount = len(enabledServers(config.ManagedMCPServers))
	state.Detail = "MCP discovery uses `" + strings.Join(command, " ") +
		"`; LLM API stays launch-scoped."
	return state
}

func reconcileOpencode(config Config, opencodeHome string) MountTargetState {
	state := placeholderState("opencode", "OpenCode", true, true, true)
	available := binaryExists("opencode")
	configHome := strings.TrimSpace(opencodeHome)
	if configHome == "" {
		configHome = defaultOpencodeHome()
	}
	configPath := filepath.Join(configHome, "config.toml")
	content, _ := os.ReadFile(configPath)
	discovered := countMCPSections(string(content))
	managedServers := enabledServers(config.ManagedMCPServers)
	if available && config.AutoSync && len(managedServers) > 0 {
		_ = applyManagedBlock(
			configPath,
			buildOpencodeManagedMCPBlock(managedServers),
			opencodeManagedMCPBlockStart,
			opencodeManagedMCPBlockEnd,
		)
	}
	state.Available = available
	if available {
		state.DiscoveryState = "ready"
	} else {
		state.DiscoveryState = "missing"
	}
	switch {
	case !available:
		state.SyncState = "missing"
	case config.AutoSync:
		state.SyncState = "ready"
	default:
		state.SyncState = "disabled"
	}
	state.DiscoveredMCPCount = discovered
	state.ManagedMCPCount = len(managedServers)
	state.Detail = "Managed MCP config is preserved in ~/.opencode/config.toml."
	return state
}

func reconcileOpenClaw(config Config, openClawHome string) MountTargetState {
	state := placeholderState("openclaw", "OpenClaw", true, false, true)
	available := binaryExists("openclaw")
	state.Available = available
	if available {
		state.DiscoveryState = "ready"
	} else {
		state.DiscoveryState = "missing"
	}
	if available && config.AutoSync {
		state.SyncState = "launch-only"
	} else {
		state.SyncState = "disabled"
	}
	state.Detail = "OpenClaw acts as the host/control plane mount."

	configHome := strings.TrimSpace(openClawHome)
	if configHome == "" {
		configHome = defaultOpenClawHome()
	}
	configPath := filepath.Join(configHome, "openclaw.json")
	if content, err := os.ReadFile(configPath); err == nil {
		var decoded map[string]any
		if err := json.Unmarshal(content, &decoded); err == nil {
			agents := 0
			if rawAgents, ok := decoded["agents"].(map[string]any); ok {
				if rawList, ok := rawAgents["list"].([]any); ok {
					agents = len(rawList)
				}
			}
			skillsDir := filepath.Join(configHome, "skills")
			if entries, err := os.ReadDir(skillsDir); err == nil {
				state.DiscoveredSkillCount = len(entries)
			}
			state.Detail = "agents: " + itoa(agents) + " · skills: " +
				itoa(state.DiscoveredSkillCount)
		} else {
			state.Detail = "OpenClaw config detected but could not be fully parsed."
		}
	}
	return state
}

func placeholderState(
	targetID string,
	label string,
	supportsSkills bool,
	supportsMCP bool,
	supportsAIGatewayInjection bool,
) MountTargetState {
	return MountTargetState{
		TargetID:                   targetID,
		Label:                      label,
		SupportsSkills:             supportsSkills,
		SupportsMCP:                supportsMCP,
		SupportsAIGatewayInjection: supportsAIGatewayInjection,
		DiscoveryState:             "idle",
		SyncState:                  "idle",
	}
}

func codexAvailable(configuredPath string) bool {
	if strings.TrimSpace(configuredPath) != "" {
		if _, err := os.Stat(strings.TrimSpace(configuredPath)); err == nil {
			return true
		}
	}
	return binaryExists("codex")
}

func binaryExists(command string) bool {
	_, err := exec.LookPath(command)
	return err == nil
}

func countListedEntries(command []string) int {
	output := strings.TrimSpace(runCommand(command))
	if output == "" ||
		strings.Contains(output, "No MCP servers configured") ||
		strings.Contains(output, "No MCP servers configured yet") ||
		strings.Contains(output, "No MCP servers configured.") {
		return 0
	}
	lines := strings.Split(output, "\n")
	count := 0
	for _, line := range lines {
		trimmed := strings.TrimSpace(line)
		switch {
		case trimmed == "":
		case strings.HasPrefix(trimmed, "Usage:"):
		case strings.HasPrefix(trimmed, "┌"):
		case strings.HasPrefix(trimmed, "│"):
		case strings.HasPrefix(trimmed, "└"):
		default:
			count++
		}
	}
	return count
}

func runCommand(command []string) string {
	if len(command) == 0 {
		return ""
	}
	ctx, cancel := context.WithTimeout(context.Background(), 4*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, command[0], command[1:]...)
	output, err := cmd.CombinedOutput()
	if err != nil && len(output) == 0 {
		return ""
	}
	return string(output)
}

func enabledServers(servers []ManagedMCPServer) []ManagedMCPServer {
	filtered := make([]ManagedMCPServer, 0, len(servers))
	for _, server := range servers {
		if !server.Enabled {
			continue
		}
		filtered = append(filtered, server)
	}
	sort.SliceStable(filtered, func(i, j int) bool {
		return filtered[i].ID < filtered[j].ID
	})
	return filtered
}

func enabledCodexServers(servers []ManagedMCPServer) []ManagedMCPServer {
	filtered := make([]ManagedMCPServer, 0, len(servers))
	for _, server := range servers {
		if !server.Enabled || strings.TrimSpace(server.Command) == "" {
			continue
		}
		filtered = append(filtered, server)
	}
	sort.SliceStable(filtered, func(i, j int) bool {
		return filtered[i].ID < filtered[j].ID
	})
	return filtered
}

func itoa(value int) string {
	return strconv.Itoa(value)
}
