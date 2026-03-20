package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"strings"
	"time"
)

type rpcRequest struct {
	JSONRPC string         `json:"jsonrpc,omitempty"`
	ID      any            `json:"id,omitempty"`
	Method  string         `json:"method,omitempty"`
	Params  map[string]any `json:"params,omitempty"`
}

type toolCallParams struct {
	Name      string         `json:"name"`
	Arguments map[string]any `json:"arguments"`
}

func main() {
	reader := bufio.NewReader(os.Stdin)
	for {
		payload, err := readMessage(reader)
		if err != nil {
			if errors.Is(err, io.EOF) {
				return
			}
			writeError(nil, -32700, err.Error())
			continue
		}
		if len(bytes.TrimSpace(payload)) == 0 {
			continue
		}

		var request rpcRequest
		if err := json.Unmarshal(payload, &request); err != nil {
			writeError(nil, -32700, fmt.Sprintf("invalid json: %v", err))
			continue
		}

		response := handleRequest(request)
		if response != nil {
			writeMessage(response)
		}
	}
}

func readMessage(reader *bufio.Reader) ([]byte, error) {
	line, err := reader.ReadString('\n')
	if err != nil {
		return nil, err
	}
	line = strings.TrimSpace(line)
	if line == "" {
		return nil, nil
	}
	if strings.HasPrefix(strings.ToLower(line), "content-length:") {
		var contentLength int
		if _, err := fmt.Sscanf(line, "Content-Length: %d", &contentLength); err != nil {
			if _, err2 := fmt.Sscanf(line, "content-length: %d", &contentLength); err2 != nil {
				return nil, fmt.Errorf("invalid content-length header")
			}
		}
		for {
			headerLine, err := reader.ReadString('\n')
			if err != nil {
				return nil, err
			}
			if strings.TrimSpace(headerLine) == "" {
				break
			}
		}
		body := make([]byte, contentLength)
		if _, err := io.ReadFull(reader, body); err != nil {
			return nil, err
		}
		return body, nil
	}
	return []byte(line), nil
}

func writeMessage(message map[string]any) {
	payload, _ := json.Marshal(message)
	_, _ = os.Stdout.Write(append(payload, '\n'))
}

func writeError(id any, code int, message string) {
	writeMessage(map[string]any{
		"jsonrpc": "2.0",
		"id":      id,
		"error": map[string]any{
			"code":    code,
			"message": message,
		},
	})
}

func handleRequest(request rpcRequest) map[string]any {
	if request.ID == nil {
		return nil
	}

	switch request.Method {
	case "initialize":
		return map[string]any{
			"jsonrpc": "2.0",
			"id":      request.ID,
			"result": map[string]any{
				"protocolVersion": "2024-11-05",
				"capabilities": map[string]any{
					"tools": map[string]any{},
				},
				"serverInfo": map[string]any{
					"name":    "xworkmate-aris-bridge",
					"version": "0.1.0",
				},
			},
		}
	case "ping":
		return map[string]any{
			"jsonrpc": "2.0",
			"id":      request.ID,
			"result":  map[string]any{},
		}
	case "tools/list":
		return map[string]any{
			"jsonrpc": "2.0",
			"id":      request.ID,
			"result": map[string]any{
				"tools": []map[string]any{
					{
						"name":        "chat",
						"description": "OpenAI-compatible reviewer chat bridge",
						"inputSchema": map[string]any{
							"type": "object",
							"properties": map[string]any{
								"prompt": map[string]any{"type": "string"},
								"model":  map[string]any{"type": "string"},
								"system": map[string]any{"type": "string"},
							},
							"required": []string{"prompt"},
						},
					},
					{
						"name":        "claude_review",
						"description": "Review-only bridge over Claude CLI",
						"inputSchema": map[string]any{
							"type": "object",
							"properties": map[string]any{
								"prompt": map[string]any{"type": "string"},
								"model":  map[string]any{"type": "string"},
								"system": map[string]any{"type": "string"},
								"tools":  map[string]any{"type": "string"},
							},
							"required": []string{"prompt"},
						},
					},
				},
			},
		}
	case "tools/call":
		var params toolCallParams
		raw, _ := json.Marshal(request.Params)
		if err := json.Unmarshal(raw, &params); err != nil {
			return errorResponse(request.ID, -32602, fmt.Sprintf("invalid tool params: %v", err))
		}
		switch params.Name {
		case "chat":
			content, err := handleChatTool(params.Arguments)
			if err != nil {
				return toolErrorResult(request.ID, err)
			}
			return toolTextResult(request.ID, content)
		case "claude_review":
			content, err := handleClaudeReviewTool(params.Arguments)
			if err != nil {
				return toolErrorResult(request.ID, err)
			}
			return toolTextResult(request.ID, content)
		default:
			return errorResponse(request.ID, -32601, fmt.Sprintf("unknown tool: %s", params.Name))
		}
	default:
		return errorResponse(request.ID, -32601, fmt.Sprintf("unknown method: %s", request.Method))
	}
}

func errorResponse(id any, code int, message string) map[string]any {
	return map[string]any{
		"jsonrpc": "2.0",
		"id":      id,
		"error": map[string]any{
			"code":    code,
			"message": message,
		},
	}
}

func toolTextResult(id any, content string) map[string]any {
	return map[string]any{
		"jsonrpc": "2.0",
		"id":      id,
		"result": map[string]any{
			"content": []map[string]any{
				{"type": "text", "text": content},
			},
		},
	}
}

func toolErrorResult(id any, err error) map[string]any {
	return map[string]any{
		"jsonrpc": "2.0",
		"id":      id,
		"result": map[string]any{
			"content": []map[string]any{
				{"type": "text", "text": fmt.Sprintf("Error: %v", err)},
			},
			"isError": true,
		},
	}
}

func handleChatTool(arguments map[string]any) (string, error) {
	apiKey := strings.TrimSpace(envOrDefault("LLM_API_KEY", ""))
	if apiKey == "" {
		return "", errors.New("LLM_API_KEY environment variable not set")
	}
	baseURL := normalizeBaseURL(envOrDefault("LLM_BASE_URL", "https://api.openai.com/v1"))
	model := stringArg(arguments, "model", envOrDefault("LLM_MODEL", "gpt-4o"))
	prompt := strings.TrimSpace(stringArg(arguments, "prompt", ""))
	if prompt == "" {
		return "", errors.New("prompt is required")
	}
	system := strings.TrimSpace(stringArg(arguments, "system", ""))

	messages := make([]map[string]string, 0, 2)
	if system != "" {
		messages = append(messages, map[string]string{"role": "system", "content": system})
	}
	messages = append(messages, map[string]string{"role": "user", "content": prompt})
	return callOpenAICompatible(baseURL, apiKey, model, messages)
}

func handleClaudeReviewTool(arguments map[string]any) (string, error) {
	prompt := strings.TrimSpace(stringArg(arguments, "prompt", ""))
	if prompt == "" {
		return "", errors.New("prompt is required")
	}
	model := strings.TrimSpace(stringArg(arguments, "model", envOrDefault("CLAUDE_REVIEW_MODEL", "")))
	system := strings.TrimSpace(stringArg(arguments, "system", envOrDefault("CLAUDE_REVIEW_SYSTEM", "")))
	tools := strings.TrimSpace(stringArg(arguments, "tools", envOrDefault("CLAUDE_REVIEW_TOOLS", "")))
	timeout := intArg(envOrDefault("CLAUDE_REVIEW_TIMEOUT_SEC", "600"), 600)
	return runClaudeReview(prompt, model, system, tools, time.Duration(timeout)*time.Second)
}

func callOpenAICompatible(baseURL, apiKey, model string, messages []map[string]string) (string, error) {
	payload := map[string]any{
		"model":      model,
		"messages":   messages,
		"max_tokens": 4096,
		"stream":     false,
	}
	body, _ := json.Marshal(payload)
	req, err := http.NewRequest(http.MethodPost, strings.TrimRight(baseURL, "/")+"/chat/completions", bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+apiKey)

	client := &http.Client{Timeout: 120 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return "", fmt.Errorf("api error %d: %s", resp.StatusCode, strings.TrimSpace(string(respBody)))
	}

	var decoded map[string]any
	if err := json.Unmarshal(respBody, &decoded); err != nil {
		return "", err
	}
	choices, _ := decoded["choices"].([]any)
	if len(choices) == 0 {
		return "", errors.New("missing choices in response")
	}
	choice, _ := choices[0].(map[string]any)
	message, _ := choice["message"].(map[string]any)
	content := strings.TrimSpace(fmt.Sprint(message["content"]))
	if content == "" || content == "<nil>" {
		return "", errors.New("empty response content")
	}
	return content, nil
}

func runClaudeReview(prompt, model, system, tools string, timeout time.Duration) (string, error) {
	claudeBin := strings.TrimSpace(envOrDefault("CLAUDE_BIN", "claude"))
	resolved, err := exec.LookPath(claudeBin)
	if err != nil {
		return "", fmt.Errorf("Claude CLI not found: %s", claudeBin)
	}

	args := []string{"-p", prompt, "--output-format", "json", "--permission-mode", "plan"}
	if model != "" {
		args = append(args, "--model", model)
	}
	if system != "" {
		args = append(args, "--system-prompt", system)
	}
	if tools != "" {
		args = append(args, "--tools", tools)
	}

	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	cmd := exec.CommandContext(ctx, resolved, args...)
	cmd.Stdin = nil
	var stdout bytes.Buffer
	var stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		if errors.Is(ctx.Err(), context.DeadlineExceeded) {
			return "", fmt.Errorf("Claude review timed out after %s", timeout)
		}
		message := strings.TrimSpace(stderr.String())
		if message == "" {
			message = err.Error()
		}
		return "", fmt.Errorf("Claude review failed: %s", message)
	}

	payload, err := parseClaudeJSON(stdout.String())
	if err != nil {
		message := strings.TrimSpace(stderr.String())
		if message != "" {
			return "", fmt.Errorf("%v. stderr: %s", err, message)
		}
		return "", err
	}
	if isError, _ := payload["is_error"].(bool); isError {
		return "", fmt.Errorf("%v", payload["result"])
	}
	response := strings.TrimSpace(fmt.Sprint(payload["result"]))
	if response == "" || response == "<nil>" {
		return "", errors.New("Claude review returned empty output")
	}
	return response, nil
}

func parseClaudeJSON(raw string) (map[string]any, error) {
	lines := strings.Split(raw, "\n")
	for i := len(lines) - 1; i >= 0; i-- {
		candidate := strings.TrimSpace(lines[i])
		if candidate == "" {
			continue
		}
		var payload map[string]any
		if err := json.Unmarshal([]byte(candidate), &payload); err == nil {
			return payload, nil
		}
	}
	return nil, errors.New("Claude CLI did not return JSON output")
}

func normalizeBaseURL(raw string) string {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		return "https://api.openai.com/v1"
	}
	if strings.HasSuffix(trimmed, "/v1") {
		return trimmed
	}
	return strings.TrimRight(trimmed, "/") + "/v1"
}

func envOrDefault(key, fallback string) string {
	value := strings.TrimSpace(os.Getenv(key))
	if value == "" {
		return fallback
	}
	return value
}

func stringArg(arguments map[string]any, key, fallback string) string {
	if arguments == nil {
		return fallback
	}
	value, ok := arguments[key]
	if !ok {
		return fallback
	}
	text := strings.TrimSpace(fmt.Sprint(value))
	if text == "" || text == "<nil>" {
		return fallback
	}
	return text
}

func intArg(raw string, fallback int) int {
	var parsed int
	if _, err := fmt.Sscanf(raw, "%d", &parsed); err != nil || parsed <= 0 {
		return fallback
	}
	return parsed
}
