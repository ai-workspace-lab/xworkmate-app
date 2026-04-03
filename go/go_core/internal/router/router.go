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
	AIGatewayBaseURL        string
	AIGatewayAPIKey         string
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
	SkillFinder    skills.Finder
	SkillInstaller skills.Installer
	MemoryService  memory.Service
	Classifier     Classifier
}

func NewResolver() Resolver {
	homeDir, _ := os.UserHomeDir()
	return Resolver{
		SkillFinder:    skills.NewDefaultFinder(),
		SkillInstaller: skills.NewDefaultInstaller(),
		MemoryService:  memory.NewService(homeDir),
		Classifier:     LLMClassifier{},
	}
}

func (r Resolver) Resolve(req Request) Result {
	mem := r.MemoryService.Load(req.WorkingDirectory)

	result := Result{
		ResolvedProviderID: strings.TrimSpace(req.ExplicitProviderID),
		ResolvedModel:      strings.TrimSpace(req.ExplicitModel),
		MemorySources:      mem.Sources,
	}

	result.ResolvedExecutionTarget, result.ResolvedEndpointTarget = r.resolveExecution(req, mem.Preferences)
	if result.ResolvedModel == "" {
		result.ResolvedModel = strings.TrimSpace(mem.Preferences.PreferredModel)
	}

	skillRequest := skills.ResolveRequest{
		Prompt:            req.Prompt,
		ExplicitSkills:    req.ExplicitSkills,
		AvailableSkills:   req.AvailableSkills,
		AllowSkillInstall: req.AllowSkillInstall,
	}
	skillResult := skills.Resolve(skillRequest, r.SkillFinder, r.SkillInstaller)
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

func (r Resolver) resolveExecution(req Request, prefs memory.Preferences) (string, string) {
	explicit := strings.TrimSpace(req.ExplicitExecutionTarget)
	if strings.EqualFold(strings.TrimSpace(req.RoutingMode), RoutingModeExplicit) && explicit != "" {
		return mapExplicitTarget(explicit)
	}

	prompt := normalize(req.Prompt)

	localTask := looksLocal(prompt)
	onlineTask := looksOnline(prompt)
	complexTask := looksComplex(prompt)

	switch {
	case localTask && complexTask:
		return ExecutionTargetMultiAgent, EndpointTargetSingleAgent
	case onlineTask && complexTask:
		return ExecutionTargetMultiAgent, EndpointTargetSingleAgent
	case localTask:
		return ExecutionTargetSingleAgent, EndpointTargetSingleAgent
	case onlineTask:
		return ExecutionTargetGateway, normalizeGatewayTarget(req.PreferredGatewayTarget)
	case complexTask:
		return ExecutionTargetMultiAgent, EndpointTargetSingleAgent
	}

	switch normalizeExecutionTarget(r.classify(req)) {
	case ExecutionTargetGateway:
		return ExecutionTargetGateway, normalizeGatewayTarget(req.PreferredGatewayTarget)
	case ExecutionTargetMultiAgent:
		return ExecutionTargetMultiAgent, EndpointTargetSingleAgent
	case ExecutionTargetSingleAgent:
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

func (r Resolver) classify(req Request) string {
	if r.Classifier == nil {
		return ""
	}
	return normalizeExecutionTarget(r.Classifier.Classify(ClassificationRequest{
		Prompt:           req.Prompt,
		AIGatewayBaseURL: req.AIGatewayBaseURL,
		AIGatewayAPIKey:  req.AIGatewayAPIKey,
	}))
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

func looksComplex(prompt string) bool {
	strongSignals := containsAny(prompt, []string{
		"multiple deliverables", "multiple outputs", "多个产物", "多个输出",
		"审阅", "复核", "汇编", "end-to-end", "end to end",
	})
	if strongSignals {
		return true
	}

	reviewSignals := containsAny(prompt, []string{
		"review", "audit", "verify", "summarize", "compare",
		"审阅", "复核", "汇总", "对比", "整理", "整合", "汇编",
	})
	multiStepSignals := containsAny(prompt, []string{
		"workflow", "pipeline", "step by step", "multi-step", "collect and",
		"analyze and", "review and", "compare and", "summarize and",
		"先", "然后", "之后",
	})
	structuredOutputSignals := containsAny(prompt, []string{
		"report", "memo", "table", "spreadsheet", "document", "deck", "slides",
		"presentation", "报告", "总结", "表格", "文档", "演示",
	})
	onlineCollectionSignals := containsAny(prompt, []string{
		"browser", "search", "news", "research", "crawl", "scrape",
		"跨浏览器", "搜索", "资讯", "采集", "检索",
	})

	score := 0
	if reviewSignals {
		score++
	}
	if multiStepSignals {
		score++
	}
	if structuredOutputSignals {
		score++
	}
	if onlineCollectionSignals && structuredOutputSignals {
		return true
	}
	return score >= 2
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
