package main

import (
	"time"

	"xworkmate/go_core/internal/shared"
)

func parseClaudeJSON(raw string) (map[string]any, error) {
	return shared.ParseClaudeJSON(raw)
}

func callOpenAICompatible(
	baseURL,
	apiKey,
	model string,
	messages []map[string]string,
) (string, error) {
	return shared.CallOpenAICompatible(baseURL, apiKey, model, messages)
}

func handleChatTool(arguments map[string]any) (string, error) {
	return shared.HandleChatTool(arguments)
}

func runClaudeReview(
	prompt,
	model,
	system,
	tools string,
	timeout time.Duration,
) (string, error) {
	return shared.RunClaudeReview(prompt, model, system, tools, timeout)
}
