package shared

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestHandleVaultKVToolReadsSecretData(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			t.Fatalf("unexpected method: %s", r.Method)
		}
		if got := r.Header.Get("X-Vault-Token"); got != "root-token" {
			t.Fatalf("unexpected token header: %s", got)
		}
		if got := r.Header.Get("X-Vault-Namespace"); got != "platform/team-a" {
			t.Fatalf("unexpected namespace header: %s", got)
		}
		if got := r.URL.Path; got != "/v1/secret/data/apps/demo" {
			t.Fatalf("unexpected request path: %s", got)
		}
		_ = json.NewEncoder(w).Encode(map[string]any{
			"data": map[string]any{
				"data": map[string]any{
					"api_key": "demo-key",
				},
				"metadata": map[string]any{
					"version": 3,
				},
			},
		})
	}))
	defer server.Close()

	t.Setenv("VAULT_SERVER_URL", server.URL)
	t.Setenv("VAULT_SERVER_ROOT_ACCESS_TOKEN", "root-token")
	t.Setenv("VAULT_NAMESPACE", "platform/team-a")

	output, err := HandleVaultKVTool(map[string]any{
		"operation": "read",
		"path":      "apps/demo",
	})
	if err != nil {
		t.Fatalf("HandleVaultKVTool returned error: %v", err)
	}
	if !strings.Contains(output, `"api_key": "demo-key"`) {
		t.Fatalf("expected secret data in output, got %s", output)
	}
}

func TestHandleVaultKVToolWritesSecretData(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			t.Fatalf("unexpected method: %s", r.Method)
		}
		if got := r.URL.Path; got != "/v1/secret/data/apps/demo" {
			t.Fatalf("unexpected request path: %s", got)
		}
		var payload map[string]any
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			t.Fatalf("decode payload: %v", err)
		}
		data := mapArg(payload["data"])
		if got := data["enabled"]; got != true {
			t.Fatalf("unexpected data payload: %v", payload)
		}
		options := mapArg(payload["options"])
		if got := options["cas"]; got != float64(2) {
			t.Fatalf("unexpected cas payload: %v", payload)
		}
		_ = json.NewEncoder(w).Encode(map[string]any{
			"data": map[string]any{
				"metadata": map[string]any{
					"version": 4,
				},
			},
		})
	}))
	defer server.Close()

	t.Setenv("VAULT_SERVER_URL", server.URL)
	t.Setenv("VAULT_SERVER_ROOT_ACCESS_TOKEN", "root-token")

	output, err := HandleVaultKVTool(map[string]any{
		"operation": "write",
		"path":      "apps/demo",
		"data": map[string]any{
			"enabled": true,
		},
		"cas": 2,
	})
	if err != nil {
		t.Fatalf("HandleVaultKVTool returned error: %v", err)
	}
	if !strings.Contains(output, `"version": 4`) {
		t.Fatalf("expected metadata in output, got %s", output)
	}
}

func TestHandleVaultKVToolListsSecretKeys(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "LIST" {
			t.Fatalf("unexpected method: %s", r.Method)
		}
		if got := r.URL.Path; got != "/v1/secret/metadata/apps" {
			t.Fatalf("unexpected request path: %s", got)
		}
		_ = json.NewEncoder(w).Encode(map[string]any{
			"data": map[string]any{
				"keys": []string{"demo", "prod"},
			},
		})
	}))
	defer server.Close()

	t.Setenv("VAULT_SERVER_URL", server.URL)
	t.Setenv("VAULT_SERVER_ROOT_ACCESS_TOKEN", "root-token")

	output, err := HandleVaultKVTool(map[string]any{
		"operation": "list",
		"path":      "apps",
	})
	if err != nil {
		t.Fatalf("HandleVaultKVTool returned error: %v", err)
	}
	if !strings.Contains(output, `"demo"`) || !strings.Contains(output, `"prod"`) {
		t.Fatalf("expected listed keys in output, got %s", output)
	}
}

func TestHandleVaultKVToolRequiresEnvironment(t *testing.T) {
	_, err := HandleVaultKVTool(map[string]any{
		"operation": "read",
		"path":      "apps/demo",
	})
	if err == nil || !strings.Contains(err.Error(), "VAULT_SERVER_URL") {
		t.Fatalf("expected missing environment error, got %v", err)
	}
}
