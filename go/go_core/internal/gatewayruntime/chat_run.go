package gatewayruntime

import "strings"

func normalizeChatRunEvent(event string, payload map[string]any) map[string]any {
	switch event {
	case "chat":
		runID := strings.TrimSpace(stringValue(payload["runId"]))
		state := strings.TrimSpace(stringValue(payload["state"]))
		if runID == "" && state == "" {
			return nil
		}
		message := asMap(payload["message"])
		assistantText := ""
		if strings.EqualFold(strings.TrimSpace(stringValue(message["role"])), "assistant") {
			assistantText = extractMessageText(message)
		}
		normalized := map[string]any{
			"runId":      runID,
			"sessionKey": strings.TrimSpace(stringValue(payload["sessionKey"])),
			"state":      state,
			"source":     "chat",
			"terminal":   state == "final" || state == "aborted" || state == "error",
		}
		if assistantText != "" {
			normalized["assistantText"] = assistantText
		}
		if errorMessage := strings.TrimSpace(stringValue(payload["errorMessage"])); errorMessage != "" {
			normalized["errorMessage"] = errorMessage
		}
		return normalized
	case "agent":
		runID := strings.TrimSpace(stringValue(payload["runId"]))
		if runID == "" {
			return nil
		}
		stream := strings.TrimSpace(stringValue(payload["stream"]))
		if !strings.EqualFold(stream, "assistant") {
			return nil
		}
		data := asMap(payload["data"])
		assistantText := strings.TrimSpace(stringValue(data["text"]))
		if assistantText == "" {
			assistantText = extractMessageText(data)
		}
		if assistantText == "" {
			return nil
		}
		sessionKey := strings.TrimSpace(stringValue(payload["sessionKey"]))
		if sessionKey == "" {
			sessionKey = strings.TrimSpace(stringValue(data["sessionKey"]))
		}
		return map[string]any{
			"runId":         runID,
			"sessionKey":    sessionKey,
			"state":         "delta",
			"source":        "agent",
			"stream":        stream,
			"assistantText": assistantText,
			"terminal":      false,
		}
	default:
		return nil
	}
}

func asList(value any) []any {
	switch typed := value.(type) {
	case []any:
		return typed
	default:
		return nil
	}
}

func extractMessageText(message map[string]any) string {
	directContent, ok := message["content"].(string)
	if ok {
		return strings.TrimSpace(directContent)
	}
	parts := make([]string, 0, 4)
	for _, part := range asList(message["content"]) {
		segment := asMap(part)
		text := strings.TrimSpace(firstNonEmpty(
			stringValue(segment["text"]),
			stringValue(segment["thinking"]),
		))
		if text != "" {
			parts = append(parts, text)
			continue
		}
		nestedContent := strings.TrimSpace(stringValue(segment["content"]))
		if nestedContent != "" {
			parts = append(parts, nestedContent)
		}
	}
	return strings.TrimSpace(strings.Join(parts, "\n"))
}
