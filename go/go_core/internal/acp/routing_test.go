package acp

import (
	"net/http"
	"net/http/httptest"
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
			expectedExecutionTarget:   "gateway",
			expectedSkillSource:       "find_skills",
			expectedNeedsSkillInstall: true,
		},
		{
			name:                      "image-video-generation-editting",
			prompt:                    "wan 图生视频并做视频编辑",
			expectedExecutionTarget:   "gateway",
			expectedSkillSource:       "find_skills",
			expectedNeedsSkillInstall: true,
		},
		{
			name:                      "video-translator",
			prompt:                    "translate video subtitles and dub the clip",
			expectedExecutionTarget:   "gateway",
			expectedSkillSource:       "find_skills",
			expectedNeedsSkillInstall: true,
		},
		{
			name:                    "browser-search-news",
			prompt:                  "跨浏览器执行并搜索最新资讯采集结果",
			expectedExecutionTarget: "gateway",
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

	projectLocalMemory := filepath.Join(workspaceDir, ".xworkmate", "memory.md")
	content, err := os.ReadFile(projectLocalMemory)
	if err != nil {
		t.Fatalf("expected memory file %s: %v", projectLocalMemory, err)
	}
	text := string(content)
	if !strings.Contains(text, "preferred-route: single-agent") {
		t.Fatalf("expected preferred route in %s, got %q", projectLocalMemory, text)
	}
	if !strings.Contains(text, "preferred-skills: PPTX") {
		t.Fatalf("expected preferred skills in %s, got %q", projectLocalMemory, text)
	}
	projectHomeMemory := filepath.Join(
		homeDir,
		"self-improving",
		"projects",
		filepath.Base(workspaceDir)+".md",
	)
	if _, err := os.Stat(projectHomeMemory); !os.IsNotExist(err) {
		t.Fatalf("expected auto memory write to stay project-local only, got stat err=%v", err)
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

func TestExecuteSessionTaskRequiresRouting(t *testing.T) {
	server := NewServer()
	_, rpcErr := server.executeSessionTask(task{
		req: shared.RPCRequest{
			ID:     "request-1",
			Method: "session.start",
			Params: map[string]any{
				"sessionId":  "session-missing-routing",
				"threadId":   "thread-missing-routing",
				"taskPrompt": "hello",
			},
		},
	})
	if rpcErr == nil {
		t.Fatalf("expected routing-required error")
	}
	if rpcErr.Message != "ROUTING_REQUIRED" {
		t.Fatalf("expected ROUTING_REQUIRED, got %#v", rpcErr)
	}
}

func TestExecuteSessionTaskAutoRoutingPromotesComplexRequestToMultiAgent(t *testing.T) {
	workspaceDir := filepath.Join(t.TempDir(), "workspace")
	if err := os.MkdirAll(workspaceDir, 0o755); err != nil {
		t.Fatalf("create workspace: %v", err)
	}

	aiGateway := httptest.NewServer(
		http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"choices":[{"message":{"content":"planner output"}}]}`))
		}),
	)
	defer aiGateway.Close()

	server := NewServer()
	response, rpcErr := server.executeSessionTask(task{
		req: shared.RPCRequest{
			Params: map[string]any{
				"sessionId":        "session-complex",
				"threadId":         "thread-complex",
				"provider":         "claude",
				"taskPrompt":       "collect latest news and summarize it into a report for review",
				"workingDirectory": workspaceDir,
				"aiGatewayBaseUrl": aiGateway.URL,
				"aiGatewayApiKey":  "test-key",
				"routing": map[string]any{
					"routingMode":            "auto",
					"preferredGatewayTarget": "local",
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
	if got := response["mode"]; got != "multi-agent" {
		t.Fatalf("expected session mode to be promoted to multi-agent, got %#v", got)
	}
	if got := response["resolvedExecutionTarget"]; got != "multi-agent" {
		t.Fatalf("expected resolved execution target multi-agent, got %#v", got)
	}
}

func TestHandleRoutingResolveAllowsSkillInstallRetry(t *testing.T) {
	tempDir := t.TempDir()
	finder := filepath.Join(tempDir, "find-skills.sh")
	installer := filepath.Join(tempDir, "install-skills.sh")
	if err := os.WriteFile(
		finder,
		[]byte("#!/bin/sh\nprintf '%s' '{\"candidates\":[{\"id\":\"video-translator\",\"label\":\"video-translator\",\"description\":\"translate video\",\"installed\":false}]}'\n"),
		0o755,
	); err != nil {
		t.Fatalf("write finder: %v", err)
	}
	if err := os.WriteFile(
		installer,
		[]byte("#!/bin/sh\nprintf '%s' '{\"candidates\":[{\"id\":\"video-translator\",\"label\":\"video-translator\",\"description\":\"translate video\",\"installed\":true}]}'\n"),
		0o755,
	); err != nil {
		t.Fatalf("write installer: %v", err)
	}
	t.Setenv("ACP_FIND_SKILLS_BIN", finder)
	t.Setenv("ACP_INSTALL_SKILL_BIN", installer)

	result := handleRoutingResolve(map[string]any{
		"taskPrompt":       "translate and dub this video with subtitles",
		"workingDirectory": "/tmp/workspace",
		"routing": map[string]any{
			"routingMode":       "auto",
			"allowSkillInstall": true,
			"availableSkills": []any{
				map[string]any{
					"id":          "docx",
					"label":       "docx",
					"description": "docs",
					"installed":   true,
				},
			},
		},
	})

	if got := result["skillResolutionSource"]; got != "find_skills" {
		t.Fatalf("expected find_skills source, got %#v", got)
	}
	if got := result["needsSkillInstall"]; got != true {
		t.Fatalf("expected first pass to request install approval, got %#v", got)
	}
	requestID, _ := result["skillInstallRequestId"].(string)
	if strings.TrimSpace(requestID) == "" {
		t.Fatalf("expected install request id, got %#v", result)
	}

	retried := handleRoutingResolve(map[string]any{
		"taskPrompt":       "translate and dub this video with subtitles",
		"workingDirectory": "/tmp/workspace",
		"routing": map[string]any{
			"routingMode":       "auto",
			"allowSkillInstall": true,
			"installApproval": map[string]any{
				"requestId":         requestID,
				"approvedSkillKeys": []any{"video-translator"},
			},
			"availableSkills": []any{
				map[string]any{
					"id":          "docx",
					"label":       "docx",
					"description": "docs",
					"installed":   true,
				},
			},
		},
	})

	if got := retried["needsSkillInstall"]; got != false {
		t.Fatalf("expected install retry to clear needsSkillInstall, got %#v", got)
	}
	resolvedSkills, _ := retried["resolvedSkills"].([]string)
	if len(resolvedSkills) != 1 || resolvedSkills[0] != "video-translator" {
		t.Fatalf("expected installed skill to resolve, got %#v", retried["resolvedSkills"])
	}
}
