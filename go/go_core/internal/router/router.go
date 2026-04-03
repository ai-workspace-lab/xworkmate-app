package router

import (
	"os"
	"strings"

	"xworkmate/go_core/internal/memory"
	"xworkmate/go_core/internal/skills"
)

const (
	RoutingModeAuto     = "auto"
	RoutingModeExplicit = "explicit"

	ExecutionTargetSingleAgent = "single-agent"
	ExecutionTargetMultiAgent  = "multi-agent"
	ExecutionTargetGateway     = "gateway"
	ExecutionTargetGatewayChat = "gateway-chat"

	EndpointTargetSingleAgent = "singleAgent"
	EndpointTargetLocal       = "local"
	EndpointTargetRemote      = "remote"
)

type Request struct {
	Prompt                  string
	WorkingDirectory        string
	RoutingMode             string
	PreferredGatewayTarget  string
	ExplicitExecutionTarget string
	ExplicitProviderID      string
	ExplicitModel           string
	ExplicitSkills          []string
	AllowSkillInstall       bool
	AvailableSkills         []skills.Candidate
}

type Result struct {
	ResolvedExecutionTarget string
	ResolvedEndpointTarget  string
	ResolvedProviderID      string
	ResolvedModel           string
	ResolvedSkills          []string
	SkillResolutionSource   string
	SkillCandidates         []skills.Candidate
	NeedsSkillInstall       bool
	MemorySources           []memory.Source
}

type Resolver struct {
	SkillFinder   skills.Finder
	MemoryService memory.Service
}

func NewResolver() Resolver {
	homeDir, _ := os.UserHomeDir()
	return Resolver{
		SkillFinder:   skills.StaticFinder{},
		MemoryService: memory.NewService(homeDir),
	}
}

func (r Resolver) Resolve(req Request) Result {
	mem := r.MemoryService.Load(req.WorkingDirectory)

	result := Result{
		ResolvedProviderID: strings.TrimSpace(req.ExplicitProviderID),
		ResolvedModel:      strings.TrimSpace(req.ExplicitModel),
		MemorySources:      mem.Sources,
	}

	result.ResolvedExecutionTarget, result.ResolvedEndpointTarget = resolveExecution(req, mem.Preferences)
	if result.ResolvedModel == "" {
		result.ResolvedModel = strings.TrimSpace(mem.Preferences.PreferredModel)
	}

	skillRequest := skills.ResolveRequest{
		Prompt:            req.Prompt,
		ExplicitSkills:    req.ExplicitSkills,
		AvailableSkills:   req.AvailableSkills,
		AllowSkillInstall: req.AllowSkillInstall,
	}
	skillResult := skills.Resolve(skillRequest, r.SkillFinder)
	result.ResolvedSkills = skillResult.ResolvedSkills
	result.SkillResolutionSource = skillResult.Source
	result.SkillCandidates = skillResult.Candidates
	result.NeedsSkillInstall = skillResult.NeedsInstall

	if len(result.ResolvedSkills) == 0 && len(mem.Preferences.PreferredSkills) > 0 {
		result.ResolvedSkills = append([]string(nil), mem.Preferences.PreferredSkills...)
		if result.SkillResolutionSource == "" || result.SkillResolutionSource == "none" {
			result.SkillResolutionSource = "local_match"
		}
	}
	if result.SkillResolutionSource == "" {
		result.SkillResolutionSource = "none"
	}
	if result.ResolvedExecutionTarget == "" {
		result.ResolvedExecutionTarget = ExecutionTargetSingleAgent
	}
	if result.ResolvedEndpointTarget == "" {
		result.ResolvedEndpointTarget = EndpointTargetSingleAgent
	}
	return result
}

func resolveExecution(req Request, prefs memory.Preferences) (string, string) {
	explicit := strings.TrimSpace(req.ExplicitExecutionTarget)
	if strings.EqualFold(strings.TrimSpace(req.RoutingMode), RoutingModeExplicit) && explicit != "" {
		return mapExplicitTarget(explicit)
	}

	prompt := normalize(req.Prompt)
	if looksOnline(prompt) {
		return ExecutionTargetGateway, normalizeGatewayTarget(req.PreferredGatewayTarget)
	}
	if looksLocal(prompt) {
		return ExecutionTargetSingleAgent, EndpointTargetSingleAgent
	}

	switch normalizeExecutionTarget(strings.TrimSpace(prefs.PreferredRoute)) {
	case ExecutionTargetGateway:
		return ExecutionTargetGateway, normalizeGatewayTarget(req.PreferredGatewayTarget)
	case ExecutionTargetMultiAgent:
		return ExecutionTargetMultiAgent, EndpointTargetSingleAgent
	}
	return ExecutionTargetSingleAgent, EndpointTargetSingleAgent
}

func mapExplicitTarget(value string) (string, string) {
	switch strings.TrimSpace(value) {
	case EndpointTargetLocal:
		return ExecutionTargetGateway, EndpointTargetLocal
	case EndpointTargetRemote:
		return ExecutionTargetGateway, EndpointTargetRemote
	case "multiAgent", ExecutionTargetMultiAgent:
		return ExecutionTargetMultiAgent, EndpointTargetSingleAgent
	case EndpointTargetSingleAgent, ExecutionTargetSingleAgent:
		return ExecutionTargetSingleAgent, EndpointTargetSingleAgent
	default:
		return ExecutionTargetSingleAgent, EndpointTargetSingleAgent
	}
}

func normalizeGatewayTarget(value string) string {
	switch strings.TrimSpace(value) {
	case EndpointTargetLocal:
		return EndpointTargetLocal
	default:
		return EndpointTargetRemote
	}
}

func looksLocal(prompt string) bool {
	return containsAny(prompt, []string{
		"ppt", "pptx", "powerpoint", "word", "docx", "excel", "xlsx", "pdf",
		"image-resizer", "resize image", "compress image", "crop image",
	})
}

func looksOnline(prompt string) bool {
	return containsAny(prompt, []string{
		"image-cog", "wan", "video-translator", "browser", "search", "news",
		"资讯采集", "跨浏览器", "文生图", "文生视频", "图生视频", "视频翻译",
		"translate video", "dub video", "subtitles",
	})
}

func containsAny(haystack string, needles []string) bool {
	for _, needle := range needles {
		if strings.Contains(haystack, normalize(needle)) {
			return true
		}
	}
	return false
}

func normalize(value string) string {
	return strings.ToLower(strings.TrimSpace(value))
}

func normalizeExecutionTarget(value string) string {
	switch normalize(value) {
	case ExecutionTargetGatewayChat:
		return ExecutionTargetGateway
	default:
		return normalize(value)
	}
}
