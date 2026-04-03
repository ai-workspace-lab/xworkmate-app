package skills

import (
	"context"
	"encoding/json"
	"fmt"
	"os/exec"
	"strings"
	"time"

	"xworkmate/go_core/internal/shared"
)

type ChainFinder struct {
	Primary  Finder
	Fallback Finder
}

func (f ChainFinder) Find(prompt string) []Candidate {
	if f.Primary != nil {
		if resolved := dedupeCandidates(f.Primary.Find(prompt)); len(resolved) > 0 {
			return resolved
		}
	}
	if f.Fallback == nil {
		return nil
	}
	return dedupeCandidates(f.Fallback.Find(prompt))
}

type CommandFinder struct {
	Binary string
}

func (f CommandFinder) Find(prompt string) []Candidate {
	payload, ok := runSkillCommand(
		strings.TrimSpace(f.Binary),
		map[string]any{"prompt": strings.TrimSpace(prompt)},
	)
	if !ok {
		return nil
	}
	return parseCandidatesPayload(payload)
}

type CommandInstaller struct {
	Binary string
}

func (i CommandInstaller) Install(candidates []Candidate) ([]Candidate, error) {
	payload, ok := runSkillCommand(
		strings.TrimSpace(i.Binary),
		map[string]any{
			"candidates": routingCandidatesPayload(candidates),
		},
	)
	if !ok {
		return nil, nil
	}
	return parseCandidatesPayload(payload), nil
}

func NewDefaultFinder() Finder {
	return ChainFinder{
		Primary: CommandFinder{
			Binary: strings.TrimSpace(shared.EnvOrDefault("ACP_FIND_SKILLS_BIN", "")),
		},
		Fallback: StaticFinder{},
	}
}

func NewDefaultInstaller() Installer {
	return CommandInstaller{
		Binary: strings.TrimSpace(shared.EnvOrDefault("ACP_INSTALL_SKILL_BIN", "")),
	}
}

func runSkillCommand(binary string, payload map[string]any) (map[string]any, bool) {
	if binary == "" {
		return nil, false
	}
	if _, err := exec.LookPath(binary); err != nil {
		return nil, false
	}
	body, err := json.Marshal(payload)
	if err != nil {
		return nil, false
	}
	ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, binary)
	cmd.Stdin = strings.NewReader(string(body))
	output, err := cmd.Output()
	if err != nil {
		return nil, false
	}
	var decoded map[string]any
	if err := json.Unmarshal(output, &decoded); err == nil {
		return decoded, true
	}
	var list []map[string]any
	if err := json.Unmarshal(output, &list); err == nil {
		return map[string]any{"candidates": list}, true
	}
	return nil, false
}

func parseCandidatesPayload(payload map[string]any) []Candidate {
	if len(payload) == 0 {
		return nil
	}
	if raw, ok := payload["candidates"]; ok {
		return parseCandidates(raw)
	}
	if raw, ok := payload["skills"]; ok {
		return parseCandidates(raw)
	}
	return parseCandidates(payload)
}

func parseCandidates(raw any) []Candidate {
	switch typed := raw.(type) {
	case []any:
		result := make([]Candidate, 0, len(typed))
		for _, item := range typed {
			entry := toMap(item)
			if len(entry) == 0 {
				continue
			}
			result = append(result, Candidate{
				ID:          strings.TrimSpace(stringValue(entry["id"])),
				Label:       strings.TrimSpace(stringValue(entry["label"])),
				Description: strings.TrimSpace(stringValue(entry["description"])),
				Installed:   boolValue(entry["installed"]),
			})
		}
		return dedupeCandidates(result)
	case []map[string]any:
		values := make([]any, 0, len(typed))
		for _, item := range typed {
			values = append(values, item)
		}
		return parseCandidates(values)
	case map[string]any:
		entry := Candidate{
			ID:          strings.TrimSpace(stringValue(typed["id"])),
			Label:       strings.TrimSpace(stringValue(typed["label"])),
			Description: strings.TrimSpace(stringValue(typed["description"])),
			Installed:   boolValue(typed["installed"]),
		}
		if entry.ID == "" && entry.Label == "" {
			return nil
		}
		return []Candidate{entry}
	default:
		return nil
	}
}

func routingCandidatesPayload(candidates []Candidate) []map[string]any {
	result := make([]map[string]any, 0, len(candidates))
	for _, candidate := range candidates {
		result = append(result, map[string]any{
			"id":          strings.TrimSpace(candidate.ID),
			"label":       strings.TrimSpace(candidate.Label),
			"description": strings.TrimSpace(candidate.Description),
			"installed":   candidate.Installed,
		})
	}
	return result
}

func toMap(value any) map[string]any {
	if typed, ok := value.(map[string]any); ok {
		return typed
	}
	if typed, ok := value.(map[string]interface{}); ok {
		return typed
	}
	return nil
}

func stringValue(value any) string {
	if value == nil {
		return ""
	}
	switch typed := value.(type) {
	case string:
		return strings.TrimSpace(typed)
	default:
		return strings.TrimSpace(fmt.Sprint(value))
	}
}

func boolValue(value any) bool {
	switch typed := value.(type) {
	case bool:
		return typed
	case string:
		normalized := strings.ToLower(strings.TrimSpace(typed))
		return normalized == "true" || normalized == "1" || normalized == "yes"
	case float64:
		return typed != 0
	case int:
		return typed != 0
	default:
		return false
	}
}
