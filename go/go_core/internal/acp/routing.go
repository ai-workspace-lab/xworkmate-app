package acp

import (
	"fmt"
	"os"
	"strings"

	"xworkmate/go_core/internal/memory"
	"xworkmate/go_core/internal/router"
	"xworkmate/go_core/internal/skills"
)

func handleRoutingResolve(params map[string]any) map[string]any {
	result, _ := resolveRoutingMetadata(params)
	return mergeRoutingResponse(map[string]any{"ok": true}, result)
}

func resolveRoutingMetadata(params map[string]any) (router.Result, bool) {
	routingParams := asMap(params["routing"])
	if len(routingParams) == 0 {
		return router.Result{}, false
	}

	resolver := router.NewResolver()
	result := resolver.Resolve(router.Request{
		Prompt:                  strings.TrimSpace(sharedString(params, "taskPrompt")),
		WorkingDirectory:        strings.TrimSpace(sharedString(params, "workingDirectory")),
		RoutingMode:             strings.TrimSpace(sharedString(routingParams, "routingMode")),
		PreferredGatewayTarget:  strings.TrimSpace(sharedString(routingParams, "preferredGatewayTarget")),
		ExplicitExecutionTarget: strings.TrimSpace(sharedString(routingParams, "explicitExecutionTarget")),
		ExplicitProviderID:      strings.TrimSpace(sharedString(routingParams, "explicitProviderId")),
		ExplicitModel:           strings.TrimSpace(sharedString(routingParams, "explicitModel")),
		ExplicitSkills:          parseRoutingStringSlice(routingParams["explicitSkills"]),
		AllowSkillInstall:       parseBool(routingParams["allowSkillInstall"]),
		AvailableSkills:         parseRoutingSkillCandidates(routingParams["availableSkills"]),
		AIGatewayBaseURL:        strings.TrimSpace(sharedString(params, "aiGatewayBaseUrl")),
		AIGatewayAPIKey:         strings.TrimSpace(sharedString(params, "aiGatewayApiKey")),
	})
	return result, true
}

func mergeRoutingResponse(response map[string]any, result router.Result) map[string]any {
	if response == nil {
		response = map[string]any{}
	}
	response["resolvedExecutionTarget"] = result.ResolvedExecutionTarget
	response["resolvedEndpointTarget"] = result.ResolvedEndpointTarget
	response["resolvedProviderId"] = result.ResolvedProviderID
	response["resolvedModel"] = result.ResolvedModel
	response["resolvedSkills"] = append([]string(nil), result.ResolvedSkills...)
	response["skillResolutionSource"] = result.SkillResolutionSource
	response["needsSkillInstall"] = result.NeedsSkillInstall
	if len(result.SkillCandidates) > 0 {
		response["skillCandidates"] = routingSkillCandidatesMap(result.SkillCandidates)
	}
	if len(result.MemorySources) > 0 {
		response["memorySources"] = routingMemorySourcesMap(result.MemorySources)
	}
	return response
}

func recordRoutingSuccess(
	params map[string]any,
	result router.Result,
	response map[string]any,
) error {
	routingParams := asMap(params["routing"])
	if len(routingParams) == 0 {
		return nil
	}
	if strings.EqualFold(
		strings.TrimSpace(sharedString(routingParams, "routingMode")),
		router.RoutingModeExplicit,
	) {
		return nil
	}
	if !parseBool(response["success"]) {
		return nil
	}

	workingDirectory := strings.TrimSpace(sharedString(params, "workingDirectory"))
	if workingDirectory == "" {
		return nil
	}
	homeDir, _ := os.UserHomeDir()
	service := memory.NewService(homeDir)
	return service.RecordSuccess(workingDirectory, memory.SuccessEntry{
		ResolvedExecutionTarget: result.ResolvedExecutionTarget,
		ResolvedProviderID:      result.ResolvedProviderID,
		ResolvedModel:           result.ResolvedModel,
		ResolvedSkills:          append([]string(nil), result.ResolvedSkills...),
	})
}

func applyResolvedRouting(params map[string]any, result router.Result) map[string]any {
	if len(params) == 0 {
		return params
	}
	next := make(map[string]any, len(params)+6)
	for key, value := range params {
		next[key] = value
	}
	switch result.ResolvedExecutionTarget {
	case router.ExecutionTargetSingleAgent:
		next["mode"] = router.ExecutionTargetSingleAgent
	case router.ExecutionTargetMultiAgent:
		next["mode"] = router.ExecutionTargetMultiAgent
	case router.ExecutionTargetGateway:
		next["mode"] = router.ExecutionTargetGatewayChat
		if strings.TrimSpace(result.ResolvedEndpointTarget) != "" {
			next["executionTarget"] = strings.TrimSpace(result.ResolvedEndpointTarget)
		}
	}
	if strings.TrimSpace(result.ResolvedProviderID) != "" {
		next["provider"] = strings.TrimSpace(result.ResolvedProviderID)
	}
	if strings.TrimSpace(result.ResolvedModel) != "" {
		next["model"] = strings.TrimSpace(result.ResolvedModel)
	}
	if len(result.ResolvedSkills) > 0 {
		next["selectedSkills"] = append([]string(nil), result.ResolvedSkills...)
	}
	return next
}

func parseRoutingSkillCandidates(raw any) []skills.Candidate {
	list, ok := raw.([]any)
	if !ok {
		return nil
	}
	candidates := make([]skills.Candidate, 0, len(list))
	for _, item := range list {
		entry := asMap(item)
		candidates = append(candidates, skills.Candidate{
			ID:          strings.TrimSpace(sharedString(entry, "id")),
			Label:       strings.TrimSpace(sharedString(entry, "label")),
			Description: strings.TrimSpace(sharedString(entry, "description")),
			Installed:   parseBool(entry["installed"]),
		})
	}
	return candidates
}

func routingSkillCandidatesMap(candidates []skills.Candidate) []map[string]any {
	result := make([]map[string]any, 0, len(candidates))
	for _, candidate := range candidates {
		result = append(result, map[string]any{
			"id":          candidate.ID,
			"label":       candidate.Label,
			"description": candidate.Description,
			"installed":   candidate.Installed,
		})
	}
	return result
}

func routingMemorySourcesMap(sources []memory.Source) []map[string]any {
	result := make([]map[string]any, 0, len(sources))
	for _, source := range sources {
		result = append(result, map[string]any{
			"path":  source.Path,
			"scope": source.Scope,
		})
	}
	return result
}

func parseRoutingStringSlice(raw any) []string {
	list, ok := raw.([]any)
	if !ok {
		if typed, ok := raw.([]string); ok {
			return append([]string(nil), typed...)
		}
		return nil
	}
	values := make([]string, 0, len(list))
	for _, item := range list {
		value := strings.TrimSpace(sharedStringArg(item))
		if value == "" {
			continue
		}
		values = append(values, value)
	}
	return values
}

func sharedString(params map[string]any, key string) string {
	if params == nil {
		return ""
	}
	return strings.TrimSpace(sharedStringArg(params[key]))
}

func sharedStringArg(value any) string {
	if value == nil {
		return ""
	}
	switch typed := value.(type) {
	case string:
		return typed
	default:
		return fmt.Sprint(value)
	}
}
