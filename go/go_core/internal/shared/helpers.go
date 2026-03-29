package shared

import (
	"fmt"
	"os"
	"strings"
)

func NormalizeBaseURL(raw string) string {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		return "https://api.openai.com/v1"
	}
	if strings.HasSuffix(trimmed, "/v1") {
		return trimmed
	}
	return strings.TrimRight(trimmed, "/") + "/v1"
}

func EnvOrDefault(key, fallback string) string {
	value := strings.TrimSpace(os.Getenv(key))
	if value == "" {
		return fallback
	}
	return value
}

func StringArg(arguments map[string]any, key, fallback string) string {
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

func ListArg(arguments map[string]any, key string) []any {
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

func IntArg(raw string, fallback int) int {
	var parsed int
	if _, err := fmt.Sscanf(raw, "%d", &parsed); err != nil || parsed <= 0 {
		return fallback
	}
	return parsed
}

func BoolArg(raw string, fallback bool) bool {
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
