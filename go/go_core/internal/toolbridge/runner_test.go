package toolbridge

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"xworkmate/go_core/internal/shared"
)

func TestHandleRequestListsVaultKVTool(t *testing.T) {
	t.Parallel()

	response := handleRequest(sharedRequest("tools/list", nil))
	result := mapStringAny(response["result"])
	tools := result["tools"].([]map[string]any)
	found := false
	for _, tool := range tools {
		if tool["name"] == "vault_kv" {
			found = true
			break
		}
	}
	if !found {
		t.Fatalf("expected vault_kv tool in %v", tools)
	}
}

func TestHandleRequestCallsVaultKVTool(t *testing.T) {
	var requestPath string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requestPath = r.URL.Path
		_ = json.NewEncoder(w).Encode(map[string]any{
			"data": map[string]any{
				"data": map[string]any{
					"demo": "value",
				},
			},
		})
	}))
	defer server.Close()

	t.Setenv("VAULT_SERVER_URL", server.URL)
	t.Setenv("VAULT_SERVER_ROOT_ACCESS_TOKEN", "root-token")

	response := handleRequest(sharedRequest("tools/call", map[string]any{
		"name": "vault_kv",
		"arguments": map[string]any{
			"operation": "read",
			"path":      "apps/demo",
		},
	}))
	result := mapStringAny(response["result"])
	content := result["content"].([]map[string]any)
	text := strings.TrimSpace(content[0]["text"].(string))
	if !strings.Contains(text, `"demo": "value"`) {
		t.Fatalf("unexpected tool output: %s", text)
	}
	if requestPath != "/v1/secret/data/apps/demo" {
		t.Fatalf("unexpected request path: %s", requestPath)
	}
}

func sharedRequest(method string, params map[string]any) shared.RPCRequest {
	return shared.RPCRequest{
		JSONRPC: "2.0",
		ID:      1,
		Method:  method,
		Params:  params,
	}
}

func mapStringAny(raw any) map[string]any {
	if typed, ok := raw.(map[string]any); ok {
		return typed
	}
	return map[string]any{}
}
