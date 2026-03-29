package toolbridge

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"strings"

	"xworkmate/go_core/internal/shared"
)

func Run(input io.Reader, output io.Writer) {
	reader := bufio.NewReader(input)
	for {
		payload, err := readMessage(reader)
		if err != nil {
			if errors.Is(err, io.EOF) {
				return
			}
			writeError(output, nil, -32700, err.Error())
			continue
		}
		if len(strings.TrimSpace(string(payload))) == 0 {
			continue
		}

		request, err := shared.DecodeRPCRequest(payload)
		if err != nil {
			writeError(output, nil, -32700, err.Error())
			continue
		}

		response := handleRequest(request)
		if response != nil {
			writeMessage(output, response)
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

func writeMessage(output io.Writer, message map[string]any) {
	payload, _ := json.Marshal(message)
	_, _ = output.Write(append(payload, '\n'))
}

func writeError(output io.Writer, id any, code int, message string) {
	writeMessage(output, shared.ErrorEnvelope(id, code, message))
}

func handleRequest(request shared.RPCRequest) map[string]any {
	if request.ID == nil {
		return nil
	}

	switch request.Method {
	case "initialize":
		return shared.ResultEnvelope(request.ID, map[string]any{
			"protocolVersion": "2024-11-05",
			"capabilities": map[string]any{
				"tools": map[string]any{},
			},
			"serverInfo": map[string]any{
				"name":    "xworkmate-go-core",
				"version": "0.2.0",
			},
		})
	case "ping":
		return shared.ResultEnvelope(request.ID, map[string]any{})
	case "tools/list":
		return shared.ResultEnvelope(request.ID, map[string]any{
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
				{
					"name":        "vault_kv",
					"description": "HashiCorp Vault K/V v2 bridge",
					"inputSchema": map[string]any{
						"type": "object",
						"properties": map[string]any{
							"operation": map[string]any{"type": "string"},
							"mount":     map[string]any{"type": "string"},
							"path":      map[string]any{"type": "string"},
							"data":      map[string]any{"type": "object"},
							"cas":       map[string]any{"type": "number"},
						},
						"required": []string{"operation", "path"},
					},
				},
			},
		})
	case "tools/call":
		var params shared.ToolCallParams
		raw, _ := json.Marshal(request.Params)
		if err := json.Unmarshal(raw, &params); err != nil {
			return shared.ErrorResponse(
				request.ID,
				-32602,
				fmt.Sprintf("invalid tool params: %v", err),
			)
		}
		switch params.Name {
		case "chat":
			content, err := shared.HandleChatTool(params.Arguments)
			if err != nil {
				return shared.ToolErrorResult(request.ID, err)
			}
			return shared.ToolTextResult(request.ID, content)
		case "claude_review":
			content, err := shared.HandleClaudeReviewTool(params.Arguments)
			if err != nil {
				return shared.ToolErrorResult(request.ID, err)
			}
			return shared.ToolTextResult(request.ID, content)
		case "vault_kv":
			content, err := shared.HandleVaultKVTool(params.Arguments)
			if err != nil {
				return shared.ToolErrorResult(request.ID, err)
			}
			return shared.ToolTextResult(request.ID, content)
		default:
			return shared.ErrorResponse(
				request.ID,
				-32601,
				fmt.Sprintf("unknown tool: %s", params.Name),
			)
		}
	default:
		return shared.ErrorResponse(
			request.ID,
			-32601,
			fmt.Sprintf("unknown method: %s", request.Method),
		)
	}
}
