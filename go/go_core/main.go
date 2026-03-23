package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

type rpcRequest struct {
	JSONRPC string         `json:"jsonrpc,omitempty"`
	ID      any            `json:"id,omitempty"`
	Method  string         `json:"method,omitempty"`
	Params  map[string]any `json:"params,omitempty"`
}

type rpcError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

type toolCallParams struct {
	Name      string         `json:"name"`
	Arguments map[string]any `json:"arguments"`
}

type acpSession struct {
	sessionID string
	threadID  string
	mode      string
	provider  string
	history   []string
	seq       int
	cancel    context.CancelFunc
	closed    bool
}

type acpTask struct {
	req    rpcRequest
	notify func(map[string]any)
	done   chan acpTaskResult
}

type acpTaskResult struct {
	response map[string]any
	err      *rpcError
}

type acpServer struct {
	mu       sync.Mutex
	sessions map[string]*acpSession
	queues   map[string]chan acpTask
}

var wsUpgrader = websocket.Upgrader{
	ReadBufferSize:  16 * 1024,
	WriteBufferSize: 16 * 1024,
	CheckOrigin: func(*http.Request) bool {
		return true
	},
}

func main() {
	if len(os.Args) > 1 && os.Args[1] == "serve" {
		serveACP()
		return
	}
	runToolBridge()
}

func serveACP() {
	flags := flag.NewFlagSet("serve", flag.ExitOnError)
	listen := flags.String(
		"listen",
		envOrDefault("ACP_LISTEN_ADDR", "127.0.0.1:8787"),
		"ACP listen address",
	)
	_ = flags.Parse(os.Args[2:])

	server := newACPServer()
	mux := http.NewServeMux()
	mux.HandleFunc("/acp", server.handleWebSocket)
	mux.HandleFunc("/acp/rpc", server.handleRPC)

	httpServer := &http.Server{
		Addr:         strings.TrimSpace(*listen),
		Handler:      mux,
		ReadTimeout:  30 * time.Second,
		WriteTimeout: 5 * time.Minute,
		IdleTimeout:  2 * time.Minute,
	}

	if err := httpServer.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		fmt.Fprintf(os.Stderr, "ACP server failed: %v\n", err)
		os.Exit(1)
	}
}

func runToolBridge() {
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

		response := handleToolBridgeRequest(request)
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

func handleToolBridgeRequest(request rpcRequest) map[string]any {
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
					"name":    "xworkmate-go-core",
					"version": "0.2.0",
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

func newACPServer() *acpServer {
	return &acpServer{
		sessions: make(map[string]*acpSession),
		queues:   make(map[string]chan acpTask),
	}
}

func (s *acpServer) handleWebSocket(w http.ResponseWriter, r *http.Request) {
	conn, err := wsUpgrader.Upgrade(w, r, nil)
	if err != nil {
		return
	}
	defer conn.Close()

	var writeMu sync.Mutex
	notify := func(message map[string]any) {
		writeMu.Lock()
		defer writeMu.Unlock()
		_ = conn.WriteJSON(message)
	}

	for {
		_, payload, err := conn.ReadMessage()
		if err != nil {
			return
		}
		request, err := decodeRpcRequest(payload)
		if err != nil {
			notify(errorEnvelope(nil, -32700, err.Error()))
			continue
		}
		response, rpcErr := s.handleACPRequest(request, notify)
		if request.ID == nil {
			continue
		}
		if rpcErr != nil {
			notify(errorEnvelope(request.ID, rpcErr.Code, rpcErr.Message))
			continue
		}
		notify(resultEnvelope(request.ID, response))
	}
}

func (s *acpServer) handleRPC(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	payload, err := io.ReadAll(r.Body)
	if err != nil {
		w.WriteHeader(http.StatusBadRequest)
		_, _ = w.Write([]byte("invalid body"))
		return
	}
	request, err := decodeRpcRequest(payload)
	if err != nil {
		w.WriteHeader(http.StatusBadRequest)
		_, _ = w.Write([]byte(err.Error()))
		return
	}

	accept := strings.ToLower(r.Header.Get("Accept"))
	stream := strings.Contains(accept, "text/event-stream")
	if stream {
		w.Header().Set("Content-Type", "text/event-stream")
		w.Header().Set("Cache-Control", "no-cache")
		w.Header().Set("Connection", "keep-alive")
	}

	flusher, _ := w.(http.Flusher)
	writeNotification := func(message map[string]any) {
		if !stream {
			return
		}
		writeSSE(w, message)
		if flusher != nil {
			flusher.Flush()
		}
	}

	response, rpcErr := s.handleACPRequest(request, writeNotification)
	if request.ID == nil {
		if stream {
			_, _ = w.Write([]byte("data: [DONE]\n\n"))
		}
		return
	}
	if rpcErr != nil {
		envelope := errorEnvelope(request.ID, rpcErr.Code, rpcErr.Message)
		if stream {
			writeSSE(w, envelope)
			if flusher != nil {
				flusher.Flush()
			}
			return
		}
		w.WriteHeader(http.StatusOK)
		_ = json.NewEncoder(w).Encode(envelope)
		return
	}
	if stream {
		writeSSE(w, resultEnvelope(request.ID, response))
		if flusher != nil {
			flusher.Flush()
		}
		return
	}
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(resultEnvelope(request.ID, response))
}

func (s *acpServer) handleACPRequest(request rpcRequest, notify func(map[string]any)) (map[string]any, *rpcError) {
	method := strings.TrimSpace(request.Method)
	switch method {
	case "acp.capabilities":
		providers := detectACPProviders()
		singleAgent := len(providers) > 0
		multiAgent := boolArg(envOrDefault("ACP_MULTI_AGENT_ENABLED", "true"), true)
		result := map[string]any{
			"singleAgent": singleAgent,
			"multiAgent":  multiAgent,
			"providers":   providers,
			"capabilities": map[string]any{
				"single_agent": singleAgent,
				"multi_agent":  multiAgent,
				"providers":    providers,
			},
		}
		return result, nil
	case "session.start", "session.message":
		params := request.Params
		sessionID := strings.TrimSpace(stringArg(params, "sessionId", ""))
		if sessionID == "" {
			return nil, &rpcError{Code: -32602, Message: "sessionId is required"}
		}
		threadID := strings.TrimSpace(stringArg(params, "threadId", sessionID))
		if threadID == "" {
			threadID = sessionID
		}
		if method == "session.start" {
			s.resetSession(sessionID, threadID)
		}
		result, rpcErr := s.enqueue(threadID, acpTask{
			req:    request,
			notify: notify,
			done:   make(chan acpTaskResult, 1),
		})
		if rpcErr != nil {
			return nil, rpcErr
		}
		return result, nil
	case "session.cancel":
		params := request.Params
		sessionID := strings.TrimSpace(stringArg(params, "sessionId", ""))
		if sessionID == "" {
			return nil, &rpcError{Code: -32602, Message: "sessionId is required"}
		}
		cancelled := s.cancelSession(sessionID)
		return map[string]any{"accepted": true, "cancelled": cancelled}, nil
	case "session.close":
		params := request.Params
		sessionID := strings.TrimSpace(stringArg(params, "sessionId", ""))
		if sessionID == "" {
			return nil, &rpcError{Code: -32602, Message: "sessionId is required"}
		}
		closed := s.closeSession(sessionID)
		return map[string]any{"accepted": true, "closed": closed}, nil
	default:
		return nil, &rpcError{Code: -32601, Message: fmt.Sprintf("unknown method: %s", method)}
	}
}

func (s *acpServer) enqueue(threadID string, task acpTask) (map[string]any, *rpcError) {
	queue := s.ensureQueue(threadID)
	queue <- task
	result := <-task.done
	return result.response, result.err
}

func (s *acpServer) ensureQueue(threadID string) chan acpTask {
	s.mu.Lock()
	defer s.mu.Unlock()
	queue, ok := s.queues[threadID]
	if ok {
		return queue
	}
	queue = make(chan acpTask, 32)
	s.queues[threadID] = queue
	go s.runQueue(queue)
	return queue
}

func (s *acpServer) runQueue(queue chan acpTask) {
	for task := range queue {
		response, err := s.executeSessionTask(task)
		task.done <- acpTaskResult{response: response, err: err}
	}
}

func (s *acpServer) executeSessionTask(task acpTask) (map[string]any, *rpcError) {
	params := task.req.Params
	sessionID := strings.TrimSpace(stringArg(params, "sessionId", ""))
	threadID := strings.TrimSpace(stringArg(params, "threadId", sessionID))
	mode := strings.TrimSpace(stringArg(params, "mode", "single-agent"))
	provider := strings.TrimSpace(stringArg(params, "provider", ""))
	if mode == "single-agent" && provider == "" {
		provider = "codex"
	}

	session := s.getOrCreateSession(sessionID, threadID)
	session.mode = mode
	if provider != "" {
		session.provider = provider
	}

	prompt := strings.TrimSpace(stringArg(params, "taskPrompt", ""))
	if prompt != "" {
		session.history = append(session.history, prompt)
	}
	turnID := fmt.Sprintf("turn-%d", time.Now().UnixNano())

	ctx, cancel := context.WithCancel(context.Background())
	s.setSessionCancel(sessionID, cancel)
	defer s.clearSessionCancel(sessionID)

	notify := task.notify
	s.emitSessionUpdate(session, notify, turnID, map[string]any{
		"type":    "status",
		"event":   "started",
		"message": "session started",
		"pending": true,
		"error":   false,
	})

	if mode == "multi-agent" {
		result := s.runMultiAgent(ctx, session, params, turnID, notify)
		if result.err != nil {
			return nil, result.err
		}
		return result.response, nil
	}

	result := s.runSingleAgent(ctx, session, params, turnID, notify)
	if result.err != nil {
		return nil, result.err
	}
	return result.response, nil
}

func (s *acpServer) runSingleAgent(
	ctx context.Context,
	session *acpSession,
	params map[string]any,
	turnID string,
	notify func(map[string]any),
) acpTaskResult {
	provider := session.provider
	if provider == "" {
		provider = strings.TrimSpace(stringArg(params, "provider", "codex"))
	}
	workingDirectory := strings.TrimSpace(stringArg(params, "workingDirectory", ""))
	model := strings.TrimSpace(stringArg(params, "model", ""))
	prompt := strings.TrimSpace(stringArg(params, "taskPrompt", ""))
	prompt = augmentPromptWithAttachments(prompt, params)

	output, err := runProviderCommand(ctx, provider, model, prompt, workingDirectory)
	if err != nil {
		s.emitSessionUpdate(session, notify, turnID, map[string]any{
			"type":    "status",
			"event":   "completed",
			"message": err.Error(),
			"pending": false,
			"error":   true,
		})
		return acpTaskResult{
			response: map[string]any{
				"success":  false,
				"error":    err.Error(),
				"turnId":   turnID,
				"mode":     "single-agent",
				"provider": provider,
			},
		}
	}

	s.emitSessionUpdate(session, notify, turnID, map[string]any{
		"type":    "delta",
		"delta":   output,
		"pending": false,
		"error":   false,
	})

	s.emitSessionUpdate(session, notify, turnID, map[string]any{
		"type":    "status",
		"event":   "completed",
		"message": "single-agent completed",
		"pending": false,
		"error":   false,
	})

	return acpTaskResult{
		response: map[string]any{
			"success":  true,
			"output":   output,
			"turnId":   turnID,
			"mode":     "single-agent",
			"provider": provider,
		},
	}
}

func (s *acpServer) runMultiAgent(
	ctx context.Context,
	session *acpSession,
	params map[string]any,
	turnID string,
	notify func(map[string]any),
) acpTaskResult {
	prompt := composeHistoryPrompt(session.history)
	if prompt == "" {
		prompt = strings.TrimSpace(stringArg(params, "taskPrompt", ""))
	}
	prompt = augmentPromptWithAttachments(prompt, params)

	baseURL := normalizeBaseURL(stringArg(params, "aiGatewayBaseUrl", ""))
	apiKey := strings.TrimSpace(stringArg(params, "aiGatewayApiKey", ""))
	model := strings.TrimSpace(stringArg(params, "model", envOrDefault("ACP_MULTI_AGENT_MODEL", "gpt-4o")))
	if model == "" {
		model = "gpt-4o"
	}

	s.emitSessionUpdate(session, notify, turnID, map[string]any{
		"type":      "step",
		"mode":      "multi-agent",
		"title":     "Planner",
		"message":   "Preparing multi-agent run",
		"pending":   false,
		"error":     false,
		"role":      "architect",
		"iteration": 1,
		"score":     0,
	})

	if apiKey == "" {
		errMsg := "aiGatewayApiKey is required for multi-agent mode"
		s.emitSessionUpdate(session, notify, turnID, map[string]any{
			"type":    "status",
			"mode":    "multi-agent",
			"message": errMsg,
			"pending": false,
			"error":   true,
		})
		return acpTaskResult{
			response: map[string]any{
				"success": false,
				"error":   errMsg,
				"turnId":  turnID,
				"mode":    "multi-agent",
			},
		}
	}

	messages := []map[string]string{
		{"role": "system", "content": "You are a multi-agent coordinator. Return concise actionable output."},
		{"role": "user", "content": prompt},
	}
	output, err := callOpenAICompatibleCtx(ctx, baseURL, apiKey, model, messages)
	if err != nil {
		s.emitSessionUpdate(session, notify, turnID, map[string]any{
			"type":    "status",
			"mode":    "multi-agent",
			"message": err.Error(),
			"pending": false,
			"error":   true,
		})
		return acpTaskResult{
			response: map[string]any{
				"success": false,
				"error":   err.Error(),
				"turnId":  turnID,
				"mode":    "multi-agent",
			},
		}
	}

	s.emitSessionUpdate(session, notify, turnID, map[string]any{
		"type":      "step",
		"mode":      "multi-agent",
		"title":     "Reviewer",
		"message":   output,
		"pending":   false,
		"error":     false,
		"role":      "tester",
		"iteration": 1,
		"score":     9,
	})

	return acpTaskResult{
		response: map[string]any{
			"success":    true,
			"summary":    output,
			"finalScore": 9,
			"iterations": 1,
			"turnId":     turnID,
			"mode":       "multi-agent",
		},
	}
}

func (s *acpServer) emitSessionUpdate(
	session *acpSession,
	notify func(map[string]any),
	turnID string,
	payload map[string]any,
) {
	if notify == nil {
		return
	}
	s.mu.Lock()
	session.seq++
	seq := session.seq
	s.mu.Unlock()
	params := map[string]any{
		"sessionId": session.sessionID,
		"threadId":  session.threadID,
		"turnId":    turnID,
		"seq":       seq,
	}
	for key, value := range payload {
		params[key] = value
	}
	notify(notificationEnvelope("session.update", params))
}

func (s *acpServer) getOrCreateSession(sessionID, threadID string) *acpSession {
	s.mu.Lock()
	defer s.mu.Unlock()
	if session, ok := s.sessions[sessionID]; ok {
		if threadID != "" {
			session.threadID = threadID
		}
		session.closed = false
		return session
	}
	session := &acpSession{sessionID: sessionID, threadID: threadID}
	s.sessions[sessionID] = session
	return session
}

func (s *acpServer) resetSession(sessionID, threadID string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.sessions[sessionID] = &acpSession{
		sessionID: sessionID,
		threadID:  threadID,
		history:   []string{},
	}
}

func (s *acpServer) setSessionCancel(sessionID string, cancel context.CancelFunc) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if session, ok := s.sessions[sessionID]; ok {
		session.cancel = cancel
	}
}

func (s *acpServer) clearSessionCancel(sessionID string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if session, ok := s.sessions[sessionID]; ok {
		session.cancel = nil
	}
}

func (s *acpServer) cancelSession(sessionID string) bool {
	s.mu.Lock()
	session, ok := s.sessions[sessionID]
	if !ok {
		s.mu.Unlock()
		return false
	}
	cancel := session.cancel
	s.mu.Unlock()
	if cancel != nil {
		cancel()
		return true
	}
	return false
}

func (s *acpServer) closeSession(sessionID string) bool {
	s.mu.Lock()
	session, ok := s.sessions[sessionID]
	if !ok {
		s.mu.Unlock()
		return false
	}
	cancel := session.cancel
	session.closed = true
	delete(s.sessions, sessionID)
	s.mu.Unlock()
	if cancel != nil {
		cancel()
	}
	return true
}

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
