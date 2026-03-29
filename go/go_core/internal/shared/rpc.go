package shared

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"
)

type RPCRequest struct {
	JSONRPC string         `json:"jsonrpc,omitempty"`
	ID      any            `json:"id,omitempty"`
	Method  string         `json:"method,omitempty"`
	Params  map[string]any `json:"params,omitempty"`
}

type RPCError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

type ToolCallParams struct {
	Name      string         `json:"name"`
	Arguments map[string]any `json:"arguments"`
}

func DecodeRPCRequest(payload []byte) (RPCRequest, error) {
	var request RPCRequest
	if err := json.Unmarshal(payload, &request); err != nil {
		return RPCRequest{}, fmt.Errorf("invalid json: %w", err)
	}
	if strings.TrimSpace(request.Method) == "" {
		return RPCRequest{}, errors.New("missing method")
	}
	if request.Params == nil {
		request.Params = map[string]any{}
	}
	return request, nil
}

func WriteSSE(w http.ResponseWriter, payload map[string]any) {
	encoded, _ := json.Marshal(payload)
	_, _ = fmt.Fprintf(w, "data: %s\n\n", encoded)
}

func ResultEnvelope(id any, result map[string]any) map[string]any {
	return map[string]any{
		"jsonrpc": "2.0",
		"id":      id,
		"result":  result,
	}
}

func ErrorEnvelope(id any, code int, message string) map[string]any {
	return map[string]any{
		"jsonrpc": "2.0",
		"id":      id,
		"error": map[string]any{
			"code":    code,
			"message": message,
		},
	}
}

func NotificationEnvelope(method string, params map[string]any) map[string]any {
	return map[string]any{
		"jsonrpc": "2.0",
		"method":  method,
		"params":  params,
	}
}

func ErrorResponse(id any, code int, message string) map[string]any {
	return map[string]any{
		"jsonrpc": "2.0",
		"id":      id,
		"error": map[string]any{
			"code":    code,
			"message": message,
		},
	}
}

func ToolTextResult(id any, content string) map[string]any {
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

func ToolErrorResult(id any, err error) map[string]any {
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
