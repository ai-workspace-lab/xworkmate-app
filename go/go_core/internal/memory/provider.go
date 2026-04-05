package memory

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

type Source struct {
	Path  string
	Scope string
}

type Preferences struct {
	PreferredRoute  string
	PreferredModel  string
	PreferredSkills []string
	Provider        string
}

type LoadResult struct {
	MergedText   string
	Sources      []Source
	Preferences  Preferences
	ProjectFiles []string
}

type SuccessEntry struct {
	ResolvedExecutionTarget string
	ResolvedProviderID      string
	ResolvedModel           string
	ResolvedSkills          []string
	Summary                 string
}

type Service struct {
	HomeDir string
}

func NewService(homeDir string) Service {
	return Service{HomeDir: strings.TrimSpace(homeDir)}
}

func (s Service) Load(workingDirectory string) LoadResult {
	projectName := projectNameFromWorkingDirectory(workingDirectory)
	paths := []Source{
		{Path: filepath.Join(s.HomeDir, "self-improving", "memory.md"), Scope: "global"},
		{Path: filepath.Join(s.HomeDir, "self-improving", "projects", projectName+".md"), Scope: "project-home"},
		{Path: filepath.Join(strings.TrimSpace(workingDirectory), ".xworkmate", "memory.md"), Scope: "project-local"},
	}
	merged := make([]string, 0, len(paths))
	sources := make([]Source, 0, len(paths))
	prefs := Preferences{}
	projectFiles := make([]string, 0, 2)

	for _, source := range paths {
		if strings.TrimSpace(source.Path) == "" {
			continue
		}
		content, err := os.ReadFile(source.Path)
		if err != nil {
			continue
		}
		text := sanitizeMemoryText(string(content))
		if strings.TrimSpace(text) == "" {
			continue
		}
		sources = append(sources, source)
		merged = append(merged, fmt.Sprintf("## %s\n%s", source.Scope, text))
		mergePreferences(&prefs, parsePreferences(text))
		if source.Scope != "global" {
			projectFiles = append(projectFiles, source.Path)
		}
	}

	return LoadResult{
		MergedText:   strings.TrimSpace(strings.Join(merged, "\n\n")),
		Sources:      sources,
		Preferences:  prefs,
		ProjectFiles: projectFiles,
	}
}

func (s Service) RecordSuccess(workingDirectory string, entry SuccessEntry) error {
	workingDirectory = strings.TrimSpace(workingDirectory)
	if workingDirectory == "" {
		return nil
	}
	projectName := projectNameFromWorkingDirectory(workingDirectory)
	if projectName == "" {
		return nil
	}
	target := s.projectWriteTarget(workingDirectory, projectName)
	if target == "" {
		return nil
	}
	block := formatSuccessEntry(entry)
	if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
		return err
	}
	file, err := os.OpenFile(target, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	if err != nil {
		return err
	}
	if _, err := file.WriteString(block); err != nil {
		_ = file.Close()
		return err
	}
	if err := file.Close(); err != nil {
		return err
	}
	return nil
}

func (s Service) projectWriteTarget(
	workingDirectory string,
	projectName string,
) string {
	repoLocalDir := filepath.Join(workingDirectory, ".xworkmate")
	if err := os.MkdirAll(repoLocalDir, 0o755); err == nil {
		return filepath.Join(repoLocalDir, "memory.md")
	}
	return filepath.Join(s.HomeDir, "self-improving", "projects", projectName+".md")
}

func formatSuccessEntry(entry SuccessEntry) string {
	lines := []string{
		"",
		fmt.Sprintf("## Auto route %s", time.Now().Format(time.RFC3339)),
		fmt.Sprintf("preferred-route: %s", strings.TrimSpace(entry.ResolvedExecutionTarget)),
	}
	if strings.TrimSpace(entry.ResolvedModel) != "" {
		lines = append(lines, fmt.Sprintf("preferred-model: %s", strings.TrimSpace(entry.ResolvedModel)))
	}
	if len(entry.ResolvedSkills) > 0 {
		lines = append(lines, fmt.Sprintf("preferred-skills: %s", strings.Join(entry.ResolvedSkills, ", ")))
	}
	if strings.TrimSpace(entry.ResolvedProviderID) != "" {
		lines = append(lines, fmt.Sprintf("provider: %s", strings.TrimSpace(entry.ResolvedProviderID)))
	}
	if summary := sanitizeMemoryText(entry.Summary); strings.TrimSpace(summary) != "" {
		lines = append(lines, "summary:")
		for _, line := range strings.Split(summary, "\n") {
			trimmed := strings.TrimSpace(line)
			if trimmed == "" {
				continue
			}
			lines = append(lines, fmt.Sprintf("- %s", trimmed))
		}
	}
	return strings.Join(lines, "\n") + "\n"
}

func parsePreferences(text string) Preferences {
	prefs := Preferences{}
	for _, line := range strings.Split(text, "\n") {
		trimmed := strings.TrimSpace(line)
		switch {
		case strings.HasPrefix(strings.ToLower(trimmed), "preferred-route:"):
			prefs.PreferredRoute = normalizePreferredRoute(
				strings.TrimSpace(strings.TrimPrefix(trimmed, "preferred-route:")),
			)
		case strings.HasPrefix(strings.ToLower(trimmed), "preferred-model:"):
			prefs.PreferredModel = strings.TrimSpace(strings.TrimPrefix(trimmed, "preferred-model:"))
		case strings.HasPrefix(strings.ToLower(trimmed), "preferred-skills:"):
			raw := strings.TrimSpace(strings.TrimPrefix(trimmed, "preferred-skills:"))
			for _, item := range strings.Split(raw, ",") {
				value := strings.TrimSpace(item)
				if value != "" {
					prefs.PreferredSkills = append(prefs.PreferredSkills, value)
				}
			}
		case strings.HasPrefix(strings.ToLower(trimmed), "provider:"):
			prefs.Provider = strings.TrimSpace(strings.TrimPrefix(trimmed, "provider:"))
		}
	}
	return prefs
}

func mergePreferences(dst *Preferences, src Preferences) {
	if strings.TrimSpace(src.PreferredRoute) != "" {
		dst.PreferredRoute = strings.TrimSpace(src.PreferredRoute)
	}
	if strings.TrimSpace(src.PreferredModel) != "" {
		dst.PreferredModel = strings.TrimSpace(src.PreferredModel)
	}
	if len(src.PreferredSkills) > 0 {
		dst.PreferredSkills = append([]string(nil), src.PreferredSkills...)
	}
	if strings.TrimSpace(src.Provider) != "" {
		dst.Provider = strings.TrimSpace(src.Provider)
	}
}

func sanitizeMemoryText(text string) string {
	lines := strings.Split(text, "\n")
	filtered := make([]string, 0, len(lines))
	for _, line := range lines {
		normalized := strings.ToLower(strings.TrimSpace(line))
		if normalized == "" {
			filtered = append(filtered, "")
			continue
		}
		if strings.Contains(normalized, "token") ||
			strings.Contains(normalized, "password") ||
			strings.Contains(normalized, "secret") ||
			strings.Contains(normalized, "api_key") ||
			strings.Contains(normalized, "apikey") ||
			strings.Contains(normalized, "api key") {
			continue
		}
		filtered = append(filtered, line)
	}
	return strings.TrimSpace(strings.Join(filtered, "\n"))
}

func projectNameFromWorkingDirectory(workingDirectory string) string {
	cleaned := strings.TrimSpace(workingDirectory)
	if cleaned == "" {
		return ""
	}
	return strings.TrimSpace(filepath.Base(cleaned))
}

func normalizePreferredRoute(value string) string {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "gateway-chat":
		return "gateway"
	default:
		return strings.TrimSpace(value)
	}
}
