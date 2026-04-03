package acp

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"xworkmate/go_core/internal/shared"
)

func TestHandleRoutingResolveCoversNineScenarioBuckets(t *testing.T) {
	localAvailableSkills := []map[string]any{
		{"id": "pptx", "label": "PPTX", "description": "slides", "installed": true},
		{"id": "docx", "label": "DOCX", "description": "docs", "installed": true},
		{"id": "xlsx", "label": "XLSX", "description": "sheets", "installed": true},
		{"id": "pdf", "label": "PDF", "description": "pdf", "installed": true},
		{"id": "image-resizer", "label": "image-resizer", "description": "image resize", "installed": true},
		{"id": "browser-automation", "label": "Browser Automation", "description": "browser", "installed": true},
	}

	cases := []struct {
		name                      string
		prompt                    string
		expectedExecutionTarget   string
		expectedSkillSource       string
		expectedResolvedSkill     string
		expectedNeedsSkillInstall bool
	}{
		{
			name:                    "powerpoint-pptx",
			prompt:                  "create a powerpoint deck for this launch",
			expectedExecutionTarget: "single-agent",
			expectedSkillSource:     "local_match",
			expectedResolvedSkill:   "PPTX",
		},
		{
			name:                    "word-docx",
			prompt:                  "draft a word document memo",
			expectedExecutionTarget: "single-agent",
			expectedSkillSource:     "local_match",
			expectedResolvedSkill:   "DOCX",
		},
		{
			name:                    "excel-xlsx",
			prompt:                  "build an excel workbook with formulas",
			expectedExecutionTarget: "single-agent",
			expectedSkillSource:     "local_match",
			expectedResolvedSkill:   "XLSX",
		},
		{
			name:                    "pdf",
			prompt:                  "merge and fill this pdf form",
			expectedExecutionTarget: "single-agent",
			expectedSkillSource:     "local_match",
			expectedResolvedSkill:   "PDF",
		},
		{
			name:                    "image-resizer",
			prompt:                  "batch resize image assets",
			expectedExecutionTarget: "single-agent",
			expectedSkillSource:     "local_match",
			expectedResolvedSkill:   "image-resizer",
		},
		{
			name:                      "image-cog",
			prompt:                    "use image-cog to generate consistent characters",
			expectedExecutionTarget:   "gateway-chat",
			expectedSkillSource:       "find_skills",
			expectedNeedsSkillInstall: true,
		},
		{
			name:                      "image-video-generation-editting",
			prompt:                    "wan 图生视频并做视频编辑",
			expectedExecutionTarget:   "gateway-chat",
			expectedSkillSource:       "find_skills",
			expectedNeedsSkillInstall: true,
		},
		{
			name:                      "video-translator",
			prompt:                    "translate video subtitles and dub the clip",
			expectedExecutionTarget:   "gateway-chat",
			expectedSkillSource:       "find_skills",
			expectedNeedsSkillInstall: true,
		},
		{
			name:                    "browser-search-news",
			prompt:                  "跨浏览器执行并搜索最新资讯采集结果",
			expectedExecutionTarget: "gateway-chat",
			expectedSkillSource:     "local_match",
			expectedResolvedSkill:   "Browser Automation",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			result := handleRoutingResolve(map[string]any{
				"taskPrompt":       tc.prompt,
				"workingDirectory": "/tmp/workspace",
				"routing": map[string]any{
					"routingMode":            "auto",
					"preferredGatewayTarget": "local",
					"allowSkillInstall":      false,
					"availableSkills": func() []any {
						values := make([]any, 0, len(localAvailableSkills))
						for _, item := range localAvailableSkills {
							values = append(values, item)
						}
						return values
					}(),
				},
			})

			if got := result["resolvedExecutionTarget"]; got != tc.expectedExecutionTarget {
				t.Fatalf("expected execution target %q, got %#v", tc.expectedExecutionTarget, got)
			}
			if got := result["skillResolutionSource"]; got != tc.expectedSkillSource {
				t.Fatalf("expected skill source %q, got %#v", tc.expectedSkillSource, got)
			}
			if tc.expectedResolvedSkill != "" {
				resolvedSkills, _ := result["resolvedSkills"].([]string)
				if len(resolvedSkills) == 0 || resolvedSkills[0] != tc.expectedResolvedSkill {
					t.Fatalf("expected resolved skill %q, got %#v", tc.expectedResolvedSkill, result["resolvedSkills"])
				}
			}
			if got := result["needsSkillInstall"]; got != tc.expectedNeedsSkillInstall {
				t.Fatalf("expected needsSkillInstall=%v, got %#v", tc.expectedNeedsSkillInstall, got)
			}
		})
	}
}

func TestExecuteSessionTaskAutoRoutingRecordsProjectMemory(t *testing.T) {
	homeDir := t.TempDir()
	workspaceDir := filepath.Join(t.TempDir(), "workspace")
	if err := os.MkdirAll(workspaceDir, 0o755); err != nil {
		t.Fatalf("create workspace: %v", err)
	}

	fakeProvider := filepath.Join(t.TempDir(), "fake-claude.sh")
	if err := os.WriteFile(
		fakeProvider,
		[]byte("#!/bin/sh\nprintf 'done'\n"),
		0o755,
	); err != nil {
		t.Fatalf("write fake provider: %v", err)
	}

	t.Setenv("HOME", homeDir)
	t.Setenv("ACP_CLAUDE_BIN", fakeProvider)

	server := NewServer()
	response, rpcErr := server.executeSessionTask(task{
		req: shared.RPCRequest{
			Params: map[string]any{
				"sessionId":        "session-auto",
				"threadId":         "thread-auto",
				"mode":             "single-agent",
				"provider":         "claude",
				"taskPrompt":       "create a powerpoint deck for launch",
				"workingDirectory": workspaceDir,
				"routing": map[string]any{
					"routingMode":            "auto",
					"preferredGatewayTarget": "local",
					"availableSkills": []any{
						map[string]any{
							"id":          "pptx",
							"label":       "PPTX",
							"description": "slides",
							"installed":   true,
						},
					},
				},
			},
		},
	})
	if rpcErr != nil {
		t.Fatalf("expected success, got rpc error: %v", rpcErr)
	}
	if success, _ := response["success"].(bool); !success {
		t.Fatalf("expected success response, got %#v", response)
	}

	projectHomeMemory := filepath.Join(
		homeDir,
		"self-improving",
		"projects",
		filepath.Base(workspaceDir)+".md",
	)
	projectLocalMemory := filepath.Join(workspaceDir, ".xworkmate", "memory.md")
	for _, target := range []string{projectHomeMemory, projectLocalMemory} {
		content, err := os.ReadFile(target)
		if err != nil {
			t.Fatalf("expected memory file %s: %v", target, err)
		}
		text := string(content)
		if !strings.Contains(text, "preferred-route: single-agent") {
			t.Fatalf("expected preferred route in %s, got %q", target, text)
		}
		if !strings.Contains(text, "preferred-skills: PPTX") {
			t.Fatalf("expected preferred skills in %s, got %q", target, text)
		}
	}
}

func TestExecuteSessionTaskExplicitRoutingDoesNotRecordProjectMemory(t *testing.T) {
	homeDir := t.TempDir()
	workspaceDir := filepath.Join(t.TempDir(), "workspace")
	if err := os.MkdirAll(workspaceDir, 0o755); err != nil {
		t.Fatalf("create workspace: %v", err)
	}

	fakeProvider := filepath.Join(t.TempDir(), "fake-claude.sh")
	if err := os.WriteFile(
		fakeProvider,
		[]byte("#!/bin/sh\nprintf 'done'\n"),
		0o755,
	); err != nil {
		t.Fatalf("write fake provider: %v", err)
	}

	t.Setenv("HOME", homeDir)
	t.Setenv("ACP_CLAUDE_BIN", fakeProvider)

	server := NewServer()
	response, rpcErr := server.executeSessionTask(task{
		req: shared.RPCRequest{
			Params: map[string]any{
				"sessionId":        "session-explicit",
				"threadId":         "thread-explicit",
				"mode":             "single-agent",
				"provider":         "claude",
				"taskPrompt":       "create a powerpoint deck for launch",
				"workingDirectory": workspaceDir,
				"routing": map[string]any{
					"routingMode":             "explicit",
					"explicitExecutionTarget": "singleAgent",
					"explicitProviderId":      "claude",
					"availableSkills": []any{
						map[string]any{
							"id":          "pptx",
							"label":       "PPTX",
							"description": "slides",
							"installed":   true,
						},
					},
				},
			},
		},
	})
	if rpcErr != nil {
		t.Fatalf("expected success, got rpc error: %v", rpcErr)
	}
	if success, _ := response["success"].(bool); !success {
		t.Fatalf("expected success response, got %#v", response)
	}

	projectHomeMemory := filepath.Join(
		homeDir,
		"self-improving",
		"projects",
		filepath.Base(workspaceDir)+".md",
	)
	projectLocalMemory := filepath.Join(workspaceDir, ".xworkmate", "memory.md")
	for _, target := range []string{projectHomeMemory, projectLocalMemory} {
		if _, err := os.Stat(target); !os.IsNotExist(err) {
			t.Fatalf("expected no memory write for explicit routing at %s, err=%v", target, err)
		}
	}
}
