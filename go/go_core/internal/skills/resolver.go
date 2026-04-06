package skills

import (
	"fmt"
	"sort"
	"strings"
)

type Candidate struct {
	ID          string
	Label       string
	Description string
	Installed   bool
}

type Finder interface {
	Find(prompt string) []Candidate
}

type Installer interface {
	Install(candidates []Candidate) ([]Candidate, error)
}

type ResolveRequest struct {
	Prompt            string
	ExplicitSkills    []string
	AvailableSkills   []Candidate
	AllowSkillInstall bool
	InstallApproval   InstallApproval
}

type InstallApproval struct {
	RequestID         string
	ApprovedSkillKeys []string
}

type ResolveResult struct {
	ResolvedSkills []string
	Candidates     []Candidate
	Source         string
	NeedsInstall   bool
	InstallRequestID string
}

type StaticFinder struct{}

func (StaticFinder) Find(prompt string) []Candidate {
	haystack := normalize(prompt)
	candidates := make([]Candidate, 0, 4)
	for _, entry := range builtinCatalog {
		if !containsAny(haystack, entry.keywords) {
			continue
		}
		candidates = append(candidates, Candidate{
			ID:        entry.id,
			Label:     entry.label,
			Installed: false,
		})
	}
	return dedupeCandidates(candidates)
}

func Resolve(req ResolveRequest, finder Finder, installer Installer) ResolveResult {
	available := dedupeCandidates(req.AvailableSkills)
	explicit := normalizeList(req.ExplicitSkills)
	if len(explicit) > 0 {
		return ResolveResult{
			ResolvedSkills: explicit,
			Source:         "local_match",
		}
	}

	localMatches := matchLocalSkills(req.Prompt, available)
	if len(localMatches) > 0 {
		return ResolveResult{
			ResolvedSkills: localMatches,
			Source:         "local_match",
		}
	}

	if finder == nil {
		return ResolveResult{Source: "none"}
	}

	fallback := dedupeCandidates(finder.Find(req.Prompt))
	if len(fallback) == 0 {
		return ResolveResult{Source: "none"}
	}

	installed := make([]string, 0, len(fallback))
	uninstalled := make([]Candidate, 0, len(fallback))
	for _, candidate := range fallback {
		if matched := findInstalledMatch(candidate, available); matched != "" {
			installed = append(installed, matched)
			continue
		}
		uninstalled = append(uninstalled, candidate)
	}

	if len(installed) > 0 {
		return ResolveResult{
			ResolvedSkills: dedupeStrings(installed),
			Candidates:     fallback,
			Source:         "find_skills",
		}
	}

	installRequestID := buildInstallRequestID(uninstalled)
	if shouldInstallApprovedCandidates(req, installRequestID) &&
		installer != nil &&
		len(uninstalled) > 0 {
		approvedCandidates := filterApprovedCandidates(
			uninstalled,
			req.InstallApproval.ApprovedSkillKeys,
		)
		if len(approvedCandidates) == 0 {
			return ResolveResult{
				Candidates:       fallback,
				Source:           "find_skills",
				NeedsInstall:     true,
				InstallRequestID: installRequestID,
			}
		}
		installedCandidates, err := installer.Install(approvedCandidates)
		if err == nil && len(installedCandidates) > 0 {
			mergedAvailable := dedupeCandidates(
				append(append([]Candidate(nil), available...), installedCandidates...),
			)
			if resolved := installedMatches(fallback, mergedAvailable); len(resolved) > 0 {
				return ResolveResult{
					ResolvedSkills: resolved,
					Candidates: dedupeCandidates(
						append(append([]Candidate(nil), fallback...), installedCandidates...),
					),
					Source: "find_skills",
				}
			}
		}
	}

	return ResolveResult{
		Candidates:        fallback,
		Source:            "find_skills",
		NeedsInstall:      len(uninstalled) > 0,
		InstallRequestID:  installRequestID,
	}
}

func shouldInstallApprovedCandidates(
	req ResolveRequest,
	expectedRequestID string,
) bool {
	if !req.AllowSkillInstall || expectedRequestID == "" {
		return false
	}
	if strings.TrimSpace(req.InstallApproval.RequestID) != expectedRequestID {
		return false
	}
	return len(dedupeStrings(req.InstallApproval.ApprovedSkillKeys)) > 0
}

func filterApprovedCandidates(
	candidates []Candidate,
	approvedSkillKeys []string,
) []Candidate {
	if len(candidates) == 0 {
		return nil
	}
	approved := make(map[string]struct{}, len(approvedSkillKeys))
	for _, key := range approvedSkillKeys {
		normalized := normalize(key)
		if normalized == "" {
			continue
		}
		approved[normalized] = struct{}{}
	}
	filtered := make([]Candidate, 0, len(candidates))
	for _, candidate := range candidates {
		if _, ok := approved[normalize(candidate.ID)]; ok {
			filtered = append(filtered, candidate)
		}
	}
	return filtered
}

func buildInstallRequestID(candidates []Candidate) string {
	if len(candidates) == 0 {
		return ""
	}
	keys := make([]string, 0, len(candidates))
	for _, candidate := range candidates {
		key := normalize(candidate.ID)
		if key == "" {
			key = normalize(candidate.Label)
		}
		if key != "" {
			keys = append(keys, key)
		}
	}
	if len(keys) == 0 {
		return ""
	}
	sort.Strings(keys)
	return "skill-install:" + strings.Join(keys, ",")
}

type builtinSkill struct {
	id       string
	label    string
	keywords []string
}

var builtinCatalog = []builtinSkill{
	{id: "pptx", label: "pptx", keywords: []string{"ppt", "pptx", "powerpoint", "slides", "幻灯片", "演示文稿"}},
	{id: "docx", label: "docx", keywords: []string{"docx", "word", "word document", "文档"}},
	{id: "xlsx", label: "xlsx", keywords: []string{"xlsx", "excel", "spreadsheet", "表格", "工作表"}},
	{id: "pdf", label: "pdf", keywords: []string{"pdf", "表单", "merge pdf", "split pdf"}},
	{id: "image-resizer", label: "image-resizer", keywords: []string{"image-resizer", "resize image", "compress image", "crop image", "批量图片"}},
	{id: "image-cog", label: "image-cog", keywords: []string{"image-cog", "文生图", "图生图", "角色一致性"}},
	{id: "image-video-generation-editting", label: "image-video-generation-editting", keywords: []string{"wan", "文生视频", "图生视频", "视频生成", "视频编辑"}},
	{id: "video-translator", label: "video-translator", keywords: []string{"video-translator", "视频翻译", "配音", "字幕翻译", "translate video", "dub video", "subtitles"}},
	{id: "browser-automation", label: "Browser Automation", keywords: []string{"browser", "跨浏览器", "浏览器", "web scraping", "资讯采集", "search", "搜索", "news", "资讯"}},
	{id: "find-skills", label: "find_skills", keywords: []string{"find skills", "find_skills", "技能包", "skill package"}},
}

func matchLocalSkills(prompt string, available []Candidate) []string {
	if len(available) == 0 {
		return nil
	}
	haystack := normalize(prompt)
	if haystack == "" {
		return nil
	}

	matches := make([]string, 0, len(available))
	for _, candidate := range available {
		keywords := candidateKeywords(candidate)
		if containsAny(haystack, keywords) {
			matches = append(matches, candidateLabel(candidate))
		}
	}
	return dedupeStrings(matches)
}

func candidateKeywords(candidate Candidate) []string {
	base := []string{
		normalize(candidate.ID),
		normalize(candidate.Label),
	}
	text := normalize(strings.Join([]string{candidate.ID, candidate.Label}, " "))
	for _, entry := range builtinCatalog {
		if containsAny(text, []string{normalize(entry.id), normalize(entry.label)}) {
			base = append(base, entry.keywords...)
		}
	}
	return dedupeStrings(base)
}

func findInstalledMatch(candidate Candidate, available []Candidate) string {
	want := candidateKeywords(candidate)
	for _, item := range available {
		if containsAny(strings.Join(candidateKeywords(item), " "), want) {
			return candidateLabel(item)
		}
	}
	return ""
}

func installedMatches(candidates []Candidate, available []Candidate) []string {
	resolved := make([]string, 0, len(candidates))
	for _, candidate := range candidates {
		if matched := findInstalledMatch(candidate, available); matched != "" {
			resolved = append(resolved, matched)
		}
	}
	return dedupeStrings(resolved)
}

func candidateLabel(candidate Candidate) string {
	if strings.TrimSpace(candidate.Label) != "" {
		return strings.TrimSpace(candidate.Label)
	}
	return strings.TrimSpace(candidate.ID)
}

func containsAny(haystack string, needles []string) bool {
	for _, needle := range needles {
		if strings.TrimSpace(needle) == "" {
			continue
		}
		if strings.Contains(haystack, normalize(needle)) {
			return true
		}
	}
	return false
}

func normalize(value string) string {
	return strings.ToLower(strings.TrimSpace(value))
}

func normalizeList(values []string) []string {
	result := make([]string, 0, len(values))
	for _, value := range values {
		trimmed := strings.TrimSpace(value)
		if trimmed == "" {
			continue
		}
		result = append(result, trimmed)
	}
	return dedupeStrings(result)
}

func dedupeStrings(values []string) []string {
	if len(values) == 0 {
		return nil
	}
	seen := make(map[string]string, len(values))
	ordered := make([]string, 0, len(values))
	for _, value := range values {
		trimmed := strings.TrimSpace(value)
		if trimmed == "" {
			continue
		}
		key := normalize(trimmed)
		if _, ok := seen[key]; ok {
			continue
		}
		seen[key] = trimmed
		ordered = append(ordered, trimmed)
	}
	return ordered
}

func dedupeCandidates(values []Candidate) []Candidate {
	if len(values) == 0 {
		return nil
	}
	seen := make(map[string]struct{}, len(values))
	ordered := make([]Candidate, 0, len(values))
	for _, candidate := range values {
		key := normalize(fmt.Sprintf("%s|%s", candidate.ID, candidate.Label))
		if key == "|" {
			continue
		}
		if _, ok := seen[key]; ok {
			continue
		}
		seen[key] = struct{}{}
		ordered = append(ordered, candidate)
	}
	return ordered
}
