package router

import (
	"context"
	"strings"
	"time"

	"xworkmate/go_core/internal/shared"
)

type ClassificationRequest struct {
	Prompt           string
	AIGatewayBaseURL string
	AIGatewayAPIKey  string
}

type Classifier interface {
	Classify(req ClassificationRequest) string
}

type LLMClassifier struct{}

func (LLMClassifier) Classify(req ClassificationRequest) string {
	baseURL := shared.NormalizeBaseURL(strings.TrimSpace(req.AIGatewayBaseURL))
	apiKey := strings.TrimSpace(req.AIGatewayAPIKey)
	if baseURL == "" {
		baseURL = shared.NormalizeBaseURL(
			shared.EnvOrDefault("LLM_BASE_URL", "https://api.openai.com/v1"),
		)
	}
	if apiKey == "" {
		apiKey = strings.TrimSpace(shared.EnvOrDefault("LLM_API_KEY", ""))
	}
	if baseURL == "" || apiKey == "" {
		return ""
	}

	model := strings.TrimSpace(shared.EnvOrDefault("ACP_ROUTING_MODEL", "gpt-4o"))
	if model == "" {
		model = "gpt-4o"
	}
	ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
	defer cancel()
	content, err := shared.CallOpenAICompatibleCtx(
		ctx,
		baseURL,
		apiKey,
		model,
		[]map[string]string{
			{
				"role":    "system",
				"content": "Classify the user task into exactly one label: single-agent, multi-agent, or gateway. Return only the label.",
			},
			{
				"role":    "user",
				"content": strings.TrimSpace(req.Prompt),
			},
		},
	)
	if err != nil {
		return ""
	}
	return normalizeClassifierLabel(content)
}

func normalizeClassifierLabel(value string) string {
	normalized := strings.ToLower(strings.TrimSpace(value))
	switch {
	case strings.Contains(normalized, ExecutionTargetSingleAgent):
		return ExecutionTargetSingleAgent
	case strings.Contains(normalized, ExecutionTargetMultiAgent):
		return ExecutionTargetMultiAgent
	case strings.Contains(normalized, ExecutionTargetGateway):
		return ExecutionTargetGateway
	default:
		return ""
	}
}
