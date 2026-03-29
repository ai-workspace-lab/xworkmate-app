package mounts

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestReconcileCodexAppliesManagedBlockAndPreservesUserEntries(t *testing.T) {
	tempDir := t.TempDir()
	configuredBinary := filepath.Join(tempDir, "custom-codex")
	if err := os.WriteFile(configuredBinary, []byte("#!/bin/sh\nexit 0\n"), 0o755); err != nil {
		t.Fatalf("write configured binary: %v", err)
	}
	configPath := filepath.Join(tempDir, "config.toml")
	if err := os.WriteFile(configPath, []byte(`
[mcp_servers.user_server]
command = "user-mcp"
`), 0o644); err != nil {
		t.Fatalf("write config: %v", err)
	}

	result := Reconcile(Request{
		Config: Config{
			AutoSync: true,
			ManagedMCPServers: []ManagedMCPServer{
				{ID: "xworkmate_server", Command: "xworkmate-mcp", Args: []string{"--port", "7777"}, Enabled: true},
			},
		},
		ConfiguredCodexCLIPath: configuredBinary,
		CodexHome:              tempDir,
	})

	content, err := os.ReadFile(configPath)
	if err != nil {
		t.Fatalf("read config: %v", err)
	}
	if !strings.Contains(string(content), `[mcp_servers.user_server]`) {
		t.Fatalf("expected user entry preserved: %s", string(content))
	}
	if !strings.Contains(string(content), `[mcp_servers.xworkmate_server]`) {
		t.Fatalf("expected managed entry written: %s", string(content))
	}
	if strings.Count(string(content), codexManagedMCPBlockStart) != 1 {
		t.Fatalf("expected single managed block: %s", string(content))
	}
	if result.MountTargets[1].ManagedMCPCount != 1 {
		t.Fatalf("expected codex managed count 1, got %d", result.MountTargets[1].ManagedMCPCount)
	}
}

func TestReconcileOpencodeAppliesManagedBlockAndPreservesUserEntries(t *testing.T) {
	tempDir := t.TempDir()
	binDir := t.TempDir()
	originalPath := os.Getenv("PATH")
	t.Setenv("PATH", binDir+string(os.PathListSeparator)+originalPath)
	if err := os.WriteFile(filepath.Join(binDir, "opencode"), []byte("#!/bin/sh\nexit 0\n"), 0o755); err != nil {
		t.Fatalf("write opencode binary: %v", err)
	}
	configPath := filepath.Join(tempDir, "config.toml")
	if err := os.WriteFile(configPath, []byte(`
[model]
name = "user-default"
`), 0o644); err != nil {
		t.Fatalf("write config: %v", err)
	}

	result := Reconcile(Request{
		Config: Config{
			AutoSync: true,
			ManagedMCPServers: []ManagedMCPServer{
				{ID: "xworkmate_server", Command: "xworkmate-mcp", Args: []string{"--port", "3001"}, Enabled: true},
			},
		},
		OpencodeHome: tempDir,
	})

	content, err := os.ReadFile(configPath)
	if err != nil {
		t.Fatalf("read config: %v", err)
	}
	if !strings.Contains(string(content), `[model]`) {
		t.Fatalf("expected user config preserved: %s", string(content))
	}
	if !strings.Contains(string(content), `[mcp_servers.xworkmate_server]`) {
		t.Fatalf("expected managed opencode entry written: %s", string(content))
	}
	if strings.Count(string(content), opencodeManagedMCPBlockStart) != 1 {
		t.Fatalf("expected single opencode managed block: %s", string(content))
	}
	if result.MountTargets[4].ManagedMCPCount != 1 {
		t.Fatalf("expected opencode managed count 1, got %d", result.MountTargets[4].ManagedMCPCount)
	}
}

func TestReconcileArisReportsReadyWhenBundleAndBridgeAreAvailable(t *testing.T) {
	result := Reconcile(Request{
		Config: Config{UsesAris: true},
		Aris: ArisInput{
			Available:         true,
			BundleVersion:     "test",
			LLMChatServerPath: "mcp-server.py",
			SkillCount:        2,
			BridgeAvailable:   true,
		},
	})

	if got := result.MountTargets[0].SyncState; got != "ready" {
		t.Fatalf("expected ready aris state, got %q", got)
	}
	if got := result.ArisBundleVersion; got != "test" {
		t.Fatalf("expected bundle version test, got %q", got)
	}
}
