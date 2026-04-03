package skills

import "testing"

func TestResolvePrefersExplicitSkills(t *testing.T) {
	result := Resolve(ResolveRequest{
		Prompt:         "make a deck",
		ExplicitSkills: []string{"pptx"},
		AvailableSkills: []Candidate{
			{ID: "pptx", Label: "pptx", Installed: true},
		},
	}, StaticFinder{})

	if result.Source != "local_match" {
		t.Fatalf("expected local_match source, got %q", result.Source)
	}
	if len(result.ResolvedSkills) != 1 || result.ResolvedSkills[0] != "pptx" {
		t.Fatalf("unexpected resolved skills: %#v", result.ResolvedSkills)
	}
}

func TestResolveUsesInstalledLocalMatchesBeforeFallback(t *testing.T) {
	result := Resolve(ResolveRequest{
		Prompt: "create a PowerPoint presentation from this brief",
		AvailableSkills: []Candidate{
			{ID: "pptx", Label: "PPTX", Installed: true},
			{ID: "docx", Label: "DOCX", Installed: true},
		},
	}, StaticFinder{})

	if result.Source != "local_match" {
		t.Fatalf("expected local_match source, got %q", result.Source)
	}
	if len(result.ResolvedSkills) != 1 || result.ResolvedSkills[0] != "PPTX" {
		t.Fatalf("unexpected resolved skills: %#v", result.ResolvedSkills)
	}
}

func TestResolveFallsBackToFindSkillsCandidates(t *testing.T) {
	result := Resolve(ResolveRequest{
		Prompt:            "translate and dub this video with subtitles",
		AvailableSkills:   []Candidate{{ID: "docx", Label: "docx", Installed: true}},
		AllowSkillInstall: false,
	}, StaticFinder{})

	if result.Source != "find_skills" {
		t.Fatalf("expected find_skills source, got %q", result.Source)
	}
	if len(result.ResolvedSkills) != 0 {
		t.Fatalf("expected no installed resolved skills, got %#v", result.ResolvedSkills)
	}
	if !result.NeedsInstall {
		t.Fatalf("expected install recommendation")
	}
	if len(result.Candidates) == 0 || result.Candidates[0].ID != "video-translator" {
		t.Fatalf("unexpected fallback candidates: %#v", result.Candidates)
	}
}
