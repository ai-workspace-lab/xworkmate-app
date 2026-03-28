package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"sort"
	"strings"
	"time"
)

func detectACPProviders() []string {
	candidates := []struct {
		provider string
		envKey   string
		binary   string
	}{
		{provider: "codex", envKey: "ACP_CODEX_BIN", binary: "codex"},
		{provider: "opencode", envKey: "ACP_OPENCODE_BIN", binary: "opencode"},
		{provider: "claude", envKey: "ACP_CLAUDE_BIN", binary: "claude"},
		{provider: "gemini", envKey: "ACP_GEMINI_BIN", binary: "gemini"},
	}
	providers := make([]string, 0, len(candidates))
	for _, candidate := range candidates {
		binary := strings.TrimSpace(envOrDefault(candidate.envKey, candidate.binary))
		if binary == "" {
			continue
		}
		if _, err := exec.LookPath(binary); err == nil {
			providers = append(providers, candidate.provider)
		}
	}
	sort.Strings(providers)
	return providers
}

func runProviderCommand(
	ctx context.Context,
	provider,
	model,
	prompt,
	workingDirectory string,
) (string, error) {
	command, args := resolveProviderCommand(provider, model, prompt, workingDirectory)
	if command == "" {
		return "", fmt.Errorf("unsupported provider: %s", provider)
	}
	cmd := exec.CommandContext(ctx, command, args...)
	if strings.TrimSpace(workingDirectory) != "" {
		cmd.Dir = strings.TrimSpace(workingDirectory)
	}
	var stdout bytes.Buffer
	var stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		if errors.Is(ctx.Err(), context.Canceled) {
			return "", errors.New("run canceled")
		}
		message := strings.TrimSpace(stderr.String())
		if message == "" {
			message = err.Error()
		}
		return "", fmt.Errorf("%s run failed: %s", provider, message)
	}
	output := strings.TrimSpace(stdout.String())
	if output == "" {
		output = strings.TrimSpace(stderr.String())
	}
	if output == "" {
		return "", fmt.Errorf("%s returned empty output", provider)
	}
	return output, nil
}

func resolveProviderCommand(provider, model, prompt, cwd string) (string, []string) {
	switch strings.TrimSpace(strings.ToLower(provider)) {
	case "codex":
		binary := strings.TrimSpace(envOrDefault("ACP_CODEX_BIN", "codex"))
		args := []string{"exec", "--skip-git-repo-check", "--color", "never"}
		if strings.TrimSpace(cwd) != "" {
			args = append(args, "-C", strings.TrimSpace(cwd))
		}
		if strings.TrimSpace(model) != "" {
			args = append(args, "-m", strings.TrimSpace(model))
		}
		args = append(args, prompt)
		return binary, args
	case "opencode":
		binary := strings.TrimSpace(envOrDefault("ACP_OPENCODE_BIN", "opencode"))
		args := []string{"run", "--format", "default"}
		if strings.TrimSpace(cwd) != "" {
			args = append(args, "--dir", strings.TrimSpace(cwd))
		}
		if strings.TrimSpace(model) != "" {
			args = append(args, "-m", strings.TrimSpace(model))
		}
		args = append(args, prompt)
		return binary, args
	case "claude":
		binary := strings.TrimSpace(envOrDefault("ACP_CLAUDE_BIN", "claude"))
		if strings.TrimSpace(model) == "" {
			return binary, []string{"-p", prompt}
		}
		return binary, []string{"--model", strings.TrimSpace(model), "-p", prompt}
	case "gemini":
		binary := strings.TrimSpace(envOrDefault("ACP_GEMINI_BIN", "gemini"))
		if strings.TrimSpace(model) == "" {
			return binary, []string{"-p", prompt}
		}
		return binary, []string{"--model", strings.TrimSpace(model), "-p", prompt}
	default:
		return "", nil
	}
}

func augmentPromptWithAttachments(prompt string, params map[string]any) string {
	attachmentsRaw := listArg(params, "attachments")
	if len(attachmentsRaw) == 0 {
		return prompt
	}
	lines := make([]string, 0, len(attachmentsRaw))
	for _, raw := range attachmentsRaw {
		entry, ok := raw.(map[string]any)
		if !ok {
			continue
		}
		name := strings.TrimSpace(stringArg(entry, "name", "attachment"))
		path := strings.TrimSpace(stringArg(entry, "path", ""))
		if path == "" {
			continue
		}
		lines = append(lines, fmt.Sprintf("- %s: %s", name, path))
	}
	if len(lines) == 0 {
		return prompt
	}
	var builder strings.Builder
	builder.WriteString("User-selected local attachments:\n")
	builder.WriteString(strings.Join(lines, "\n"))
	builder.WriteString("\n\n")
	builder.WriteString(prompt)
	return builder.String()
}

func composeHistoryPrompt(history []string) string {
	if len(history) == 0 {
		return ""
	}
	var builder strings.Builder
	for index, turn := range history {
		builder.WriteString(fmt.Sprintf("## User Turn %d\n", index+1))
		builder.WriteString(turn)
		builder.WriteString("\n\n")
	}
	return strings.TrimSpace(builder.String())
}

func callOpenAICompatibleCtx(
	ctx context.Context,
	baseURL,
	apiKey,
	model string,
	messages []map[string]string,
) (string, error) {
	payload := map[string]any{
		"model":      model,
		"messages":   messages,
		"max_tokens": 4096,
		"stream":     false,
	}
	body, _ := json.Marshal(payload)
	request, err := http.NewRequestWithContext(
		ctx,
		http.MethodPost,
		strings.TrimRight(baseURL, "/")+"/chat/completions",
		bytes.NewReader(body),
	)
	if err != nil {
		return "", err
	}
	request.Header.Set("Content-Type", "application/json")
	request.Header.Set("Authorization", "Bearer "+apiKey)

	client := &http.Client{Timeout: 120 * time.Second}
	response, err := client.Do(request)
	if err != nil {
		return "", err
	}
	defer response.Body.Close()
	responseBody, err := io.ReadAll(response.Body)
	if err != nil {
		return "", err
	}
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return "", fmt.Errorf("api error %d: %s", response.StatusCode, strings.TrimSpace(string(responseBody)))
	}

	var decoded map[string]any
	if err := json.Unmarshal(responseBody, &decoded); err != nil {
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

func decodeRpcRequest(payload []byte) (rpcRequest, error) {
	var request rpcRequest
	if err := json.Unmarshal(payload, &request); err != nil {
		return rpcRequest{}, fmt.Errorf("invalid json: %w", err)
	}
	if strings.TrimSpace(request.Method) == "" {
		return rpcRequest{}, errors.New("missing method")
	}
	if request.Params == nil {
		request.Params = map[string]any{}
	}
	return request, nil
}

func writeSSE(w http.ResponseWriter, payload map[string]any) {
	encoded, _ := json.Marshal(payload)
	_, _ = fmt.Fprintf(w, "data: %s\n\n", encoded)
}

func resultEnvelope(id any, result map[string]any) map[string]any {
	return map[string]any{
		"jsonrpc": "2.0",
		"id":      id,
		"result":  result,
	}
}

func errorEnvelope(id any, code int, message string) map[string]any {
	return map[string]any{
		"jsonrpc": "2.0",
		"id":      id,
		"error": map[string]any{
			"code":    code,
			"message": message,
		},
	}
}

func notificationEnvelope(method string, params map[string]any) map[string]any {
	return map[string]any{
		"jsonrpc": "2.0",
		"method":  method,
		"params":  params,
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
	return callOpenAICompatibleCtx(context.Background(), baseURL, apiKey, model, messages)
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

func listArg(arguments map[string]any, key string) []any {
	if arguments == nil {
		return nil
	}
	raw, ok := arguments[key]
	if !ok || raw == nil {
		return nil
	}
	if values, ok := raw.([]any); ok {
		return values
	}
	if values, ok := raw.([]interface{}); ok {
		return values
	}
	return nil
}

func intArg(raw string, fallback int) int {
	var parsed int
	if _, err := fmt.Sscanf(raw, "%d", &parsed); err != nil || parsed <= 0 {
		return fallback
	}
	return parsed
}

func boolArg(raw string, fallback bool) bool {
	trimmed := strings.TrimSpace(strings.ToLower(raw))
	if trimmed == "" {
		return fallback
	}
	switch trimmed {
	case "1", "true", "yes", "on":
		return true
	case "0", "false", "no", "off":
		return false
	default:
		return fallback
	}
}
