package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestParseClaudeJSON(t *testing.T) {
	t.Parallel()

	payload, err := parseClaudeJSON("log line\n{\"result\":\"review ok\",\"is_error\":false}\n")
	if err != nil {
		t.Fatalf("parseClaudeJSON returned error: %v", err)
	}
	if got := payload["result"]; got != "review ok" {
		t.Fatalf("unexpected result: %v", got)
	}
}

func TestCallOpenAICompatible(t *testing.T) {
	t.Parallel()

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if got := r.Header.Get("Authorization"); got != "Bearer test-key" {
			t.Fatalf("unexpected auth header: %s", got)
		}
		var body map[string]any
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			t.Fatalf("decode request body: %v", err)
		}
		if got := body["model"]; got != "qwen2.5-coder:latest" {
			t.Fatalf("unexpected model: %v", got)
		}
		_ = json.NewEncoder(w).Encode(map[string]any{
			"choices": []map[string]any{
				{
					"message": map[string]any{
						"content": "review ok",
					},
				},
			},
		})
	}))
	defer server.Close()

	output, err := callOpenAICompatible(
		server.URL,
		"test-key",
		"qwen2.5-coder:latest",
		[]map[string]string{
			{"role": "user", "content": "hello"},
		},
	)
	if err != nil {
		t.Fatalf("callOpenAICompatible returned error: %v", err)
	}
	if output != "review ok" {
		t.Fatalf("unexpected output: %s", output)
	}
}
