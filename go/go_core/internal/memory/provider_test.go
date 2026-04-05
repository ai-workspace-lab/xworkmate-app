package memory

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestLoadMergesGlobalAndProjectMemoryAndSanitizesSecrets(t *testing.T) {
	tempDir := t.TempDir()
	workingDir := filepath.Join(tempDir, "workspace")
	homeDir := filepath.Join(tempDir, "home")
	if err := os.MkdirAll(filepath.Join(workingDir, ".xworkmate"), 0o755); err != nil {
		t.Fatalf("mkdir workspace: %v", err)
	}
	if err := os.MkdirAll(filepath.Join(homeDir, "self-improving", "projects"), 0o755); err != nil {
		t.Fatalf("mkdir home: %v", err)
	}
	if err := os.WriteFile(filepath.Join(homeDir, "self-improving", "memory.md"), []byte("preferred-route: gateway-chat\napi_key: hidden\n"), 0o644); err != nil {
		t.Fatalf("write global memory: %v", err)
	}
	if err := os.WriteFile(filepath.Join(homeDir, "self-improving", "projects", "workspace.md"), []byte("preferred-model: gpt-5.4\n"), 0o644); err != nil {
		t.Fatalf("write project memory: %v", err)
	}
	if err := os.WriteFile(filepath.Join(workingDir, ".xworkmate", "memory.md"), []byte("preferred-skills: pptx, pdf\npassword: hidden\n"), 0o644); err != nil {
		t.Fatalf("write local memory: %v", err)
	}

	result := NewService(homeDir).Load(workingDir)

	if len(result.Sources) != 3 {
		t.Fatalf("expected 3 memory sources, got %d", len(result.Sources))
	}
	if strings.Contains(strings.ToLower(result.MergedText), "api_key") || strings.Contains(strings.ToLower(result.MergedText), "password") {
		t.Fatalf("expected sanitized merged text, got %q", result.MergedText)
	}
	if result.Preferences.PreferredRoute != "gateway" {
		t.Fatalf("unexpected preferred route: %#v", result.Preferences)
	}
	if result.Preferences.PreferredModel != "gpt-5.4" {
		t.Fatalf("unexpected preferred model: %#v", result.Preferences)
	}
	if len(result.Preferences.PreferredSkills) != 2 {
		t.Fatalf("unexpected preferred skills: %#v", result.Preferences.PreferredSkills)
	}
}

func TestRecordSuccessWritesProjectLevelMemoryFiles(t *testing.T) {
	tempDir := t.TempDir()
	workingDir := filepath.Join(tempDir, "repo")
	homeDir := filepath.Join(tempDir, "home")
	if err := os.MkdirAll(workingDir, 0o755); err != nil {
		t.Fatalf("mkdir working dir: %v", err)
	}

	service := NewService(homeDir)
	err := service.RecordSuccess(workingDir, SuccessEntry{
		ResolvedExecutionTarget: "single-agent",
		ResolvedModel:           "gpt-5.4",
		ResolvedSkills:          []string{"pptx", "pdf"},
		Summary:                 "created a clean deck",
	})
	if err != nil {
		t.Fatalf("record success: %v", err)
	}

	repoLocalTarget := filepath.Join(workingDir, ".xworkmate", "memory.md")
	content, err := os.ReadFile(repoLocalTarget)
	if err != nil {
		t.Fatalf("read target %s: %v", repoLocalTarget, err)
	}
	text := string(content)
	if !strings.Contains(text, "preferred-route: single-agent") {
		t.Fatalf("missing preferred route in %s: %q", repoLocalTarget, text)
	}
	if strings.Contains(strings.ToLower(text), "token") {
		t.Fatalf("unexpected sensitive content in %s: %q", repoLocalTarget, text)
	}
	homeProjectTarget := filepath.Join(homeDir, "self-improving", "projects", "repo.md")
	if _, err := os.Stat(homeProjectTarget); !os.IsNotExist(err) {
		t.Fatalf("expected single project-level write target, got stat err=%v", err)
	}
}

func TestLoadLetsProjectMemoryOverrideGlobalPreferences(t *testing.T) {
	tempDir := t.TempDir()
	workingDir := filepath.Join(tempDir, "workspace")
	homeDir := filepath.Join(tempDir, "home")
	if err := os.MkdirAll(filepath.Join(workingDir, ".xworkmate"), 0o755); err != nil {
		t.Fatalf("mkdir workspace: %v", err)
	}
	if err := os.MkdirAll(filepath.Join(homeDir, "self-improving", "projects"), 0o755); err != nil {
		t.Fatalf("mkdir home: %v", err)
	}
	if err := os.WriteFile(filepath.Join(homeDir, "self-improving", "memory.md"), []byte("preferred-route: single-agent\npreferred-model: gpt-4o\npreferred-skills: docx\n"), 0o644); err != nil {
		t.Fatalf("write global memory: %v", err)
	}
	if err := os.WriteFile(filepath.Join(homeDir, "self-improving", "projects", "workspace.md"), []byte("preferred-route: gateway\npreferred-model: gpt-5.4\n"), 0o644); err != nil {
		t.Fatalf("write project home memory: %v", err)
	}
	if err := os.WriteFile(filepath.Join(workingDir, ".xworkmate", "memory.md"), []byte("preferred-route: multi-agent\npreferred-skills: pptx, pdf\n"), 0o644); err != nil {
		t.Fatalf("write project local memory: %v", err)
	}

	result := NewService(homeDir).Load(workingDir)

	if result.Preferences.PreferredRoute != "multi-agent" {
		t.Fatalf("expected project-local route to win, got %#v", result.Preferences)
	}
	if result.Preferences.PreferredModel != "gpt-5.4" {
		t.Fatalf("expected project-home model to override global, got %#v", result.Preferences)
	}
	if len(result.Preferences.PreferredSkills) != 2 || result.Preferences.PreferredSkills[0] != "pptx" {
		t.Fatalf("expected project-local skills to win, got %#v", result.Preferences.PreferredSkills)
	}
}
