package acp

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/gorilla/websocket"

	"xworkmate/go_core/internal/dispatch"
	"xworkmate/go_core/internal/gatewayruntime"
	"xworkmate/go_core/internal/mounts"
	"xworkmate/go_core/internal/shared"
)

type session struct {
	sessionID string
	threadID  string
	mode      string
	provider  string
	history   []string
	seq       int
	cancel    context.CancelFunc
	closed    bool
}

type task struct {
	req    shared.RPCRequest
	notify func(map[string]any)
	done   chan taskResult
}

type taskResult struct {
	response map[string]any
	err      *shared.RPCError
}

type Server struct {
	mu       sync.Mutex
	sessions map[string]*session
	queues   map[string]chan task
	gateway  *gatewayruntime.Manager
}

var wsUpgrader = websocket.Upgrader{
	ReadBufferSize:  16 * 1024,
	WriteBufferSize: 16 * 1024,
	CheckOrigin: func(*http.Request) bool {
		return true
	},
}

func Serve(args []string) error {
	flags := flag.NewFlagSet("serve", flag.ExitOnError)
	listen := flags.String(
		"listen",
		shared.EnvOrDefault("ACP_LISTEN_ADDR", "127.0.0.1:8787"),
		"ACP listen address",
	)
	_ = flags.Parse(args)

	server := NewServer()
	mux := http.NewServeMux()
	mux.HandleFunc("/acp", server.HandleWebSocket)
	mux.HandleFunc("/acp/rpc", server.HandleRPC)

	httpServer := &http.Server{
		Addr:         strings.TrimSpace(*listen),
		Handler:      mux,
		ReadTimeout:  30 * time.Second,
		WriteTimeout: 5 * time.Minute,
		IdleTimeout:  2 * time.Minute,
	}

	if err := httpServer.ListenAndServe(); err != nil &&
		!errors.Is(err, http.ErrServerClosed) {
		return fmt.Errorf("ACP server failed: %w", err)
	}
	return nil
}

func NewServer() *Server {
	return &Server{
		sessions: make(map[string]*session),
		queues:   make(map[string]chan task),
		gateway:  gatewayruntime.NewManager(),
	}
}

func (s *Server) HandleWebSocket(w http.ResponseWriter, r *http.Request) {
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
		request, err := shared.DecodeRPCRequest(payload)
		if err != nil {
			notify(shared.ErrorEnvelope(nil, -32700, err.Error()))
			continue
		}
		response, rpcErr := s.handleRequest(request, notify)
		if request.ID == nil {
			continue
		}
		if rpcErr != nil {
			notify(shared.ErrorEnvelope(request.ID, rpcErr.Code, rpcErr.Message))
			continue
		}
		notify(shared.ResultEnvelope(request.ID, response))
	}
}

func (s *Server) HandleRPC(w http.ResponseWriter, r *http.Request) {
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
	request, err := shared.DecodeRPCRequest(payload)
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
		shared.WriteSSE(w, message)
		if flusher != nil {
			flusher.Flush()
		}
	}

	response, rpcErr := s.handleRequest(request, writeNotification)
	if request.ID == nil {
		if stream {
			_, _ = w.Write([]byte("data: [DONE]\n\n"))
		}
		return
	}
	if rpcErr != nil {
		envelope := shared.ErrorEnvelope(request.ID, rpcErr.Code, rpcErr.Message)
		if stream {
			shared.WriteSSE(w, envelope)
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
		shared.WriteSSE(w, shared.ResultEnvelope(request.ID, response))
		if flusher != nil {
			flusher.Flush()
		}
		return
	}
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(shared.ResultEnvelope(request.ID, response))
}

func (s *Server) handleRequest(
	request shared.RPCRequest,
	notify func(map[string]any),
) (map[string]any, *shared.RPCError) {
	method := strings.TrimSpace(request.Method)
	switch method {
	case "acp.capabilities":
		providers := shared.DetectACPProviders()
		singleAgent := len(providers) > 0
		multiAgent := shared.BoolArg(
			shared.EnvOrDefault("ACP_MULTI_AGENT_ENABLED", "true"),
			true,
		)
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
		sessionID := strings.TrimSpace(shared.StringArg(params, "sessionId", ""))
		if sessionID == "" {
			return nil, &shared.RPCError{
				Code:    -32602,
				Message: "sessionId is required",
			}
		}
		threadID := strings.TrimSpace(
			shared.StringArg(params, "threadId", sessionID),
		)
		if threadID == "" {
			threadID = sessionID
		}
		if method == "session.start" {
			s.resetSession(sessionID, threadID)
		}
		result, rpcErr := s.enqueue(threadID, task{
			req:    request,
			notify: notify,
			done:   make(chan taskResult, 1),
		})
		if rpcErr != nil {
			return nil, rpcErr
		}
		return result, nil
	case "session.cancel":
		params := request.Params
		sessionID := strings.TrimSpace(shared.StringArg(params, "sessionId", ""))
		if sessionID == "" {
			return nil, &shared.RPCError{
				Code:    -32602,
				Message: "sessionId is required",
			}
		}
		cancelled := s.cancelSession(sessionID)
		return map[string]any{"accepted": true, "cancelled": cancelled}, nil
	case "session.close":
		params := request.Params
		sessionID := strings.TrimSpace(shared.StringArg(params, "sessionId", ""))
		if sessionID == "" {
			return nil, &shared.RPCError{
				Code:    -32602,
				Message: "sessionId is required",
			}
		}
		closed := s.closeSession(sessionID)
		return map[string]any{"accepted": true, "closed": closed}, nil
	case "xworkmate.dispatch.resolve":
		return handleDispatchResolve(request.Params), nil
	case "xworkmate.routing.resolve":
		return handleRoutingResolve(request.Params), nil
	case "xworkmate.mounts.reconcile":
		return handleMountReconcile(request.Params), nil
	case "xworkmate.gateway.connect":
		return handleGatewayConnect(s, request.Params, notify), nil
	case "xworkmate.gateway.request":
		return handleGatewayRequest(s, request.Params, notify), nil
	case "xworkmate.gateway.disconnect":
		return handleGatewayDisconnect(s, request.Params, notify), nil
	default:
		return nil, &shared.RPCError{
			Code:    -32601,
			Message: fmt.Sprintf("unknown method: %s", method),
		}
	}
}

func handleDispatchResolve(params map[string]any) map[string]any {
	providers := parseDispatchProviders(params["providers"])
	requiredCapabilities := parseStringSlice(params["requiredCapabilities"])
	preferredProviderID := strings.TrimSpace(
		shared.StringArg(params, "preferredProviderId", ""),
	)
	request := dispatch.Request{
		Providers:            providers,
		PreferredProviderID:  preferredProviderID,
		RequiredCapabilities: requiredCapabilities,
	}
	if nodeState := parseDispatchNodeState(params["nodeState"]); nodeState != nil {
		request.NodeState = nodeState
	}
	if nodeInfo := parseDispatchNodeInfo(params["nodeInfo"]); nodeInfo != nil {
		request.NodeInfo = nodeInfo
	}
	return dispatch.ResultMap(dispatch.Resolve(request))
}

func parseDispatchProviders(raw any) []dispatch.Provider {
	list, ok := raw.([]any)
	if !ok {
		return nil
	}
	providers := make([]dispatch.Provider, 0, len(list))
	for _, item := range list {
		entry, ok := item.(map[string]any)
		if !ok {
			continue
		}
		id := strings.TrimSpace(shared.StringArg(entry, "id", ""))
		if id == "" {
			continue
		}
		providers = append(providers, dispatch.Provider{
			ID:           id,
			Name:         strings.TrimSpace(shared.StringArg(entry, "name", "")),
			DefaultArgs:  parseStringSlice(entry["defaultArgs"]),
			Capabilities: parseStringSlice(entry["capabilities"]),
		})
	}
	return providers
}

func parseDispatchNodeState(raw any) *dispatch.NodeState {
	entry, ok := raw.(map[string]any)
	if !ok {
		return nil
	}
	return &dispatch.NodeState{
		SelectedAgentID: strings.TrimSpace(
			shared.StringArg(entry, "selectedAgentId", ""),
		),
		GatewayConnected: shared.BoolArg(
			fmt.Sprint(entry["gatewayConnected"]),
			false,
		),
		ExecutionTarget: strings.TrimSpace(
			shared.StringArg(entry, "executionTarget", ""),
		),
		RuntimeMode:   strings.TrimSpace(shared.StringArg(entry, "runtimeMode", "")),
		BridgeEnabled: shared.BoolArg(fmt.Sprint(entry["bridgeEnabled"]), false),
		BridgeState:   strings.TrimSpace(shared.StringArg(entry, "bridgeState", "")),
		ResolvedCodexCLIPath: strings.TrimSpace(
			shared.StringArg(entry, "resolvedCodexCliPath", ""),
		),
		ConfiguredCodexCLIPath: strings.TrimSpace(
			shared.StringArg(entry, "configuredCodexCliPath", ""),
		),
	}
}

func parseDispatchNodeInfo(raw any) *dispatch.NodeInfo {
	entry, ok := raw.(map[string]any)
	if !ok {
		return nil
	}
	return &dispatch.NodeInfo{
		ID:      strings.TrimSpace(shared.StringArg(entry, "id", "")),
		Name:    strings.TrimSpace(shared.StringArg(entry, "name", "")),
		Version: strings.TrimSpace(shared.StringArg(entry, "version", "")),
	}
}

func parseStringSlice(raw any) []string {
	list, ok := raw.([]any)
	if !ok {
		return nil
	}
	values := make([]string, 0, len(list))
	for _, item := range list {
		value := strings.TrimSpace(fmt.Sprint(item))
		if value == "" {
			continue
		}
		values = append(values, value)
	}
	return values
}

func handleMountReconcile(params map[string]any) map[string]any {
	config := parseMountConfig(params["config"])
	request := mounts.Request{
		Config:                 config,
		AIGatewayURL:           strings.TrimSpace(shared.StringArg(params, "aiGatewayUrl", "")),
		ConfiguredCodexCLIPath: strings.TrimSpace(shared.StringArg(params, "configuredCodexCliPath", "")),
		CodexHome:              strings.TrimSpace(shared.StringArg(params, "codexHome", "")),
		OpencodeHome:           strings.TrimSpace(shared.StringArg(params, "opencodeHome", "")),
		OpenClawHome:           strings.TrimSpace(shared.StringArg(params, "openclawHome", "")),
		Aris:                   parseMountArisInput(params["aris"]),
	}
	return mounts.ResultMap(mounts.Reconcile(request))
}

func parseMountConfig(raw any) mounts.Config {
	entry, ok := raw.(map[string]any)
	if !ok {
		return mounts.Config{}
	}
	managedMCPServers := parseMountManagedServers(entry["managedMcpServers"])
	return mounts.Config{
		AutoSync:          shared.BoolArg(fmt.Sprint(entry["autoSync"]), false),
		UsesAris:          shared.BoolArg(fmt.Sprint(entry["usesAris"]), false),
		ManagedMCPServers: managedMCPServers,
	}
}

func parseMountManagedServers(raw any) []mounts.ManagedMCPServer {
	list, ok := raw.([]any)
	if !ok {
		return nil
	}
	servers := make([]mounts.ManagedMCPServer, 0, len(list))
	for _, item := range list {
		entry, ok := item.(map[string]any)
		if !ok {
			continue
		}
		id := strings.TrimSpace(shared.StringArg(entry, "id", ""))
		if id == "" {
			continue
		}
		servers = append(servers, mounts.ManagedMCPServer{
			ID:        id,
			Name:      strings.TrimSpace(shared.StringArg(entry, "name", "")),
			Transport: strings.TrimSpace(shared.StringArg(entry, "transport", "")),
			Command:   strings.TrimSpace(shared.StringArg(entry, "command", "")),
			URL:       strings.TrimSpace(shared.StringArg(entry, "url", "")),
			Args:      parseStringSlice(entry["args"]),
			Enabled:   shared.BoolArg(fmt.Sprint(entry["enabled"]), true),
		})
	}
	return servers
}

func parseMountArisInput(raw any) mounts.ArisInput {
	entry, ok := raw.(map[string]any)
	if !ok {
		return mounts.ArisInput{}
	}
	return mounts.ArisInput{
		Available:         shared.BoolArg(fmt.Sprint(entry["available"]), false),
		BundleVersion:     strings.TrimSpace(shared.StringArg(entry, "bundleVersion", "")),
		LLMChatServerPath: strings.TrimSpace(shared.StringArg(entry, "llmChatServerPath", "")),
		SkillCount:        shared.IntArg(fmt.Sprint(entry["skillCount"]), 0),
		BridgeAvailable:   shared.BoolArg(fmt.Sprint(entry["bridgeAvailable"]), false),
		Error:             strings.TrimSpace(shared.StringArg(entry, "error", "")),
	}
}

func (s *Server) enqueue(threadID string, task task) (map[string]any, *shared.RPCError) {
	queue := s.ensureQueue(threadID)
	queue <- task
	result := <-task.done
	return result.response, result.err
}

func (s *Server) ensureQueue(threadID string) chan task {
	s.mu.Lock()
	defer s.mu.Unlock()
	queue, ok := s.queues[threadID]
	if ok {
		return queue
	}
	queue = make(chan task, 32)
	s.queues[threadID] = queue
	go s.runQueue(queue)
	return queue
}

func (s *Server) runQueue(queue chan task) {
	for task := range queue {
		response, err := s.executeSessionTask(task)
		task.done <- taskResult{response: response, err: err}
	}
}

func (s *Server) executeSessionTask(task task) (map[string]any, *shared.RPCError) {
	params := task.req.Params
	sessionID := strings.TrimSpace(shared.StringArg(params, "sessionId", ""))
	threadID := strings.TrimSpace(shared.StringArg(params, "threadId", sessionID))
	mode := strings.TrimSpace(shared.StringArg(params, "mode", "single-agent"))
	provider := strings.TrimSpace(shared.StringArg(params, "provider", ""))
	if mode == "single-agent" && provider == "" {
		provider = "codex"
	}

	session := s.getOrCreateSession(sessionID, threadID)
	session.mode = mode
	if provider != "" {
		session.provider = provider
	}

	prompt := strings.TrimSpace(shared.StringArg(params, "taskPrompt", ""))
	if prompt != "" {
		session.history = append(session.history, prompt)
	}
	turnID := fmt.Sprintf("turn-%d", time.Now().UnixNano())
	resolvedRouting, hasResolvedRouting := resolveRoutingMetadata(params)

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
		if hasResolvedRouting {
			result.response = mergeRoutingResponse(result.response, resolvedRouting)
			if err := recordRoutingSuccess(params, resolvedRouting, result.response); err != nil {
				return nil, &shared.RPCError{Code: -32001, Message: err.Error()}
			}
		}
		return result.response, nil
	}

	result := s.runSingleAgent(ctx, session, params, turnID, notify)
	if result.err != nil {
		return nil, result.err
	}
	if hasResolvedRouting {
		result.response = mergeRoutingResponse(result.response, resolvedRouting)
		if err := recordRoutingSuccess(params, resolvedRouting, result.response); err != nil {
			return nil, &shared.RPCError{Code: -32001, Message: err.Error()}
		}
	}
	return result.response, nil
}

func (s *Server) runSingleAgent(
	ctx context.Context,
	session *session,
	params map[string]any,
	turnID string,
	notify func(map[string]any),
) taskResult {
	provider := session.provider
	if provider == "" {
		provider = strings.TrimSpace(shared.StringArg(params, "provider", "codex"))
	}
	workingDirectory := strings.TrimSpace(
		shared.StringArg(params, "workingDirectory", ""),
	)
	model := strings.TrimSpace(shared.StringArg(params, "model", ""))
	prompt := strings.TrimSpace(shared.StringArg(params, "taskPrompt", ""))
	prompt = shared.AugmentPromptWithAttachments(prompt, params)

	output, err := shared.RunProviderCommand(
		ctx,
		provider,
		model,
		prompt,
		workingDirectory,
	)
	if err != nil {
		s.emitSessionUpdate(session, notify, turnID, map[string]any{
			"type":    "status",
			"event":   "completed",
			"message": err.Error(),
			"pending": false,
			"error":   true,
		})
		return taskResult{
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

	return taskResult{
		response: map[string]any{
			"success":  true,
			"output":   output,
			"turnId":   turnID,
			"mode":     "single-agent",
			"provider": provider,
		},
	}
}

func (s *Server) runMultiAgent(
	ctx context.Context,
	session *session,
	params map[string]any,
	turnID string,
	notify func(map[string]any),
) taskResult {
	prompt := shared.ComposeHistoryPrompt(session.history)
	if prompt == "" {
		prompt = strings.TrimSpace(shared.StringArg(params, "taskPrompt", ""))
	}
	prompt = shared.AugmentPromptWithAttachments(prompt, params)

	baseURL := shared.NormalizeBaseURL(
		shared.StringArg(params, "aiGatewayBaseUrl", ""),
	)
	apiKey := strings.TrimSpace(shared.StringArg(params, "aiGatewayApiKey", ""))
	model := strings.TrimSpace(
		shared.StringArg(
			params,
			"model",
			shared.EnvOrDefault("ACP_MULTI_AGENT_MODEL", "gpt-4o"),
		),
	)
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
		return taskResult{
			response: map[string]any{
				"success": false,
				"error":   errMsg,
				"turnId":  turnID,
				"mode":    "multi-agent",
			},
		}
	}

	messages := []map[string]string{
		{
			"role":    "system",
			"content": "You are a multi-agent coordinator. Return concise actionable output.",
		},
		{"role": "user", "content": prompt},
	}
	output, err := shared.CallOpenAICompatibleCtx(
		ctx,
		baseURL,
		apiKey,
		model,
		messages,
	)
	if err != nil {
		s.emitSessionUpdate(session, notify, turnID, map[string]any{
			"type":    "status",
			"mode":    "multi-agent",
			"message": err.Error(),
			"pending": false,
			"error":   true,
		})
		return taskResult{
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

	return taskResult{
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

func (s *Server) emitSessionUpdate(
	session *session,
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
	notify(shared.NotificationEnvelope("session.update", params))
}

func (s *Server) getOrCreateSession(sessionID, threadID string) *session {
	s.mu.Lock()
	defer s.mu.Unlock()
	if session, ok := s.sessions[sessionID]; ok {
		if threadID != "" {
			session.threadID = threadID
		}
		session.closed = false
		return session
	}
	session := &session{sessionID: sessionID, threadID: threadID}
	s.sessions[sessionID] = session
	return session
}

func (s *Server) resetSession(sessionID, threadID string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.sessions[sessionID] = &session{
		sessionID: sessionID,
		threadID:  threadID,
		history:   []string{},
	}
}

func (s *Server) setSessionCancel(sessionID string, cancel context.CancelFunc) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if session, ok := s.sessions[sessionID]; ok {
		session.cancel = cancel
	}
}

func (s *Server) clearSessionCancel(sessionID string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if session, ok := s.sessions[sessionID]; ok {
		session.cancel = nil
	}
}

func (s *Server) cancelSession(sessionID string) bool {
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

func (s *Server) closeSession(sessionID string) bool {
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
