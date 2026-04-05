package skills

import "testing"

type fakeFinder []Candidate

func (f fakeFinder) Find(prompt string) []Candidate {
	return append([]Candidate(nil), f...)
}

type fakeInstaller struct {
	installed []Candidate
}

func (f fakeInstaller) Install(candidates []Candidate) ([]Candidate, error) {
	return append([]Candidate(nil), f.installed...), nil
}

func TestResolvePrefersExplicitSkills(t *testing.T) {
	result := Resolve(ResolveRequest{
		Prompt:         "make a deck",
		ExplicitSkills: []string{"pptx"},
		AvailableSkills: []Candidate{
			{ID: "pptx", Label: "pptx", Installed: true},
		},
	}, StaticFinder{}, nil)

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
	}, StaticFinder{}, nil)

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
	}, StaticFinder{}, nil)

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

func TestResolveInstallsMissingSkillsWhenAuthorized(t *testing.T) {
	initial := Resolve(
		ResolveRequest{
			Prompt:            "translate and dub this video with subtitles",
			AvailableSkills:   []Candidate{{ID: "docx", Label: "docx", Installed: true}},
			AllowSkillInstall: true,
		},
		fakeFinder{
			{ID: "video-translator", Label: "video-translator", Installed: false},
		},
		fakeInstaller{
			installed: []Candidate{
				{ID: "video-translator", Label: "video-translator", Installed: true},
			},
		},
	)

	if !initial.NeedsInstall {
		t.Fatalf("expected install approval flow to pause first, got %#v", initial)
	}
	if initial.InstallRequestID == "" {
		t.Fatalf("expected install request id, got %#v", initial)
	}

	result := Resolve(
		ResolveRequest{
			Prompt:            "translate and dub this video with subtitles",
			AvailableSkills:   []Candidate{{ID: "docx", Label: "docx", Installed: true}},
			AllowSkillInstall: true,
			InstallApproval: InstallApproval{
				RequestID:         initial.InstallRequestID,
				ApprovedSkillKeys: []string{"video-translator"},
			},
		},
		fakeFinder{
			{ID: "video-translator", Label: "video-translator", Installed: false},
		},
		fakeInstaller{
			installed: []Candidate{
				{ID: "video-translator", Label: "video-translator", Installed: true},
			},
		},
	)

	if result.Source != "find_skills" {
		t.Fatalf("expected find_skills source, got %q", result.Source)
	}
	if result.NeedsInstall {
		t.Fatalf("expected install retry to resolve the skill, got %#v", result)
	}
	if len(result.ResolvedSkills) != 1 || result.ResolvedSkills[0] != "video-translator" {
		t.Fatalf("unexpected resolved skills after install: %#v", result.ResolvedSkills)
	}
}
