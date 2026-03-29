package shared

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os/exec"
	"sort"
	"strings"
	"time"
)

func DetectACPProviders() []string {
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
		binary := strings.TrimSpace(EnvOrDefault(candidate.envKey, candidate.binary))
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

func RunProviderCommand(
	ctx context.Context,
	provider,
	model,
	prompt,
	workingDirectory string,
) (string, error) {
	command, args := ResolveProviderCommand(
		provider,
		model,
		prompt,
		workingDirectory,
	)
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

func ResolveProviderCommand(
	provider,
	model,
	prompt,
	cwd string,
) (string, []string) {
	switch strings.TrimSpace(strings.ToLower(provider)) {
	case "codex":
		binary := strings.TrimSpace(EnvOrDefault("ACP_CODEX_BIN", "codex"))
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
		binary := strings.TrimSpace(EnvOrDefault("ACP_OPENCODE_BIN", "opencode"))
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
		binary := strings.TrimSpace(EnvOrDefault("ACP_CLAUDE_BIN", "claude"))
		if strings.TrimSpace(model) == "" {
			return binary, []string{"-p", prompt}
		}
		return binary, []string{
			"--model",
			strings.TrimSpace(model),
			"-p",
			prompt,
		}
	case "gemini":
		binary := strings.TrimSpace(EnvOrDefault("ACP_GEMINI_BIN", "gemini"))
		if strings.TrimSpace(model) == "" {
			return binary, []string{"-p", prompt}
		}
		return binary, []string{
			"--model",
			strings.TrimSpace(model),
			"-p",
			prompt,
		}
	default:
		return "", nil
	}
}

func AugmentPromptWithAttachments(prompt string, params map[string]any) string {
	attachmentsRaw := ListArg(params, "attachments")
	if len(attachmentsRaw) == 0 {
		return prompt
	}
	lines := make([]string, 0, len(attachmentsRaw))
	for _, raw := range attachmentsRaw {
		entry, ok := raw.(map[string]any)
		if !ok {
			continue
		}
		name := strings.TrimSpace(StringArg(entry, "name", "attachment"))
		path := strings.TrimSpace(StringArg(entry, "path", ""))
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

func ComposeHistoryPrompt(history []string) string {
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

func CallOpenAICompatibleCtx(
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
		return "", fmt.Errorf(
			"api error %d: %s",
			response.StatusCode,
			strings.TrimSpace(string(responseBody)),
		)
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

func HandleChatTool(arguments map[string]any) (string, error) {
	apiKey := strings.TrimSpace(EnvOrDefault("LLM_API_KEY", ""))
	if apiKey == "" {
		return "", errors.New("LLM_API_KEY environment variable not set")
	}
	baseURL := NormalizeBaseURL(
		EnvOrDefault("LLM_BASE_URL", "https://api.openai.com/v1"),
	)
	model := StringArg(arguments, "model", EnvOrDefault("LLM_MODEL", "gpt-4o"))
	prompt := strings.TrimSpace(StringArg(arguments, "prompt", ""))
	if prompt == "" {
		return "", errors.New("prompt is required")
	}
	system := strings.TrimSpace(StringArg(arguments, "system", ""))

	messages := make([]map[string]string, 0, 2)
	if system != "" {
		messages = append(messages, map[string]string{
			"role":    "system",
			"content": system,
		})
	}
	messages = append(messages, map[string]string{
		"role":    "user",
		"content": prompt,
	})
	return CallOpenAICompatible(baseURL, apiKey, model, messages)
}

func HandleClaudeReviewTool(arguments map[string]any) (string, error) {
	prompt := strings.TrimSpace(StringArg(arguments, "prompt", ""))
	if prompt == "" {
		return "", errors.New("prompt is required")
	}
	model := strings.TrimSpace(
		StringArg(arguments, "model", EnvOrDefault("CLAUDE_REVIEW_MODEL", "")),
	)
	system := strings.TrimSpace(
		StringArg(arguments, "system", EnvOrDefault("CLAUDE_REVIEW_SYSTEM", "")),
	)
	tools := strings.TrimSpace(
		StringArg(arguments, "tools", EnvOrDefault("CLAUDE_REVIEW_TOOLS", "")),
	)
	timeout := IntArg(EnvOrDefault("CLAUDE_REVIEW_TIMEOUT_SEC", "600"), 600)
	return RunClaudeReview(
		prompt,
		model,
		system,
		tools,
		time.Duration(timeout)*time.Second,
	)
}

func CallOpenAICompatible(
	baseURL,
	apiKey,
	model string,
	messages []map[string]string,
) (string, error) {
	return CallOpenAICompatibleCtx(
		context.Background(),
		baseURL,
		apiKey,
		model,
		messages,
	)
}

func RunClaudeReview(
	prompt,
	model,
	system,
	tools string,
	timeout time.Duration,
) (string, error) {
	claudeBin := strings.TrimSpace(EnvOrDefault("CLAUDE_BIN", "claude"))
	resolved, err := exec.LookPath(claudeBin)
	if err != nil {
		return "", fmt.Errorf("Claude CLI not found: %s", claudeBin)
	}

	args := []string{
		"-p",
		prompt,
		"--output-format",
		"json",
		"--permission-mode",
		"plan",
	}
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

	payload, err := ParseClaudeJSON(stdout.String())
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

func ParseClaudeJSON(raw string) (map[string]any, error) {
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
