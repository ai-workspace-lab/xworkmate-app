package acp

import (
	"encoding/json"
	"net/http"
	"strings"

	"xworkmate/go_core/internal/shared"
)

func (s *Server) allowedOrigins() []string {
	raw := strings.TrimSpace(shared.EnvOrDefault(
		"ACP_ALLOWED_ORIGINS",
		"https://xworkmate.svc.plus,http://localhost:*,http://127.0.0.1:*",
	))
	if raw == "" {
		return nil
	}
	parts := strings.Split(raw, ",")
	origins := make([]string, 0, len(parts))
	for _, part := range parts {
		candidate := strings.TrimSpace(part)
		if candidate == "" {
			continue
		}
		origins = append(origins, candidate)
	}
	return origins
}

func (s *Server) originAllowed(origin string) bool {
	origin = strings.TrimSpace(origin)
	if origin == "" {
		return true
	}
	for _, allowed := range s.allowedOrigins() {
		if strings.HasSuffix(allowed, ":*") {
			if strings.HasPrefix(origin, strings.TrimSuffix(allowed, "*")) {
				return true
			}
			continue
		}
		if origin == allowed {
			return true
		}
	}
	return false
}

func (s *Server) applyCORS(w http.ResponseWriter, r *http.Request) {
	origin := strings.TrimSpace(r.Header.Get("Origin"))
	if origin == "" || !s.originAllowed(origin) {
		return
	}
	headers := w.Header()
	headers.Set("Access-Control-Allow-Origin", origin)
	headers.Set("Access-Control-Allow-Methods", "POST, OPTIONS")
	headers.Set(
		"Access-Control-Allow-Headers",
		"Authorization, Content-Type, Accept",
	)
	headers.Set("Access-Control-Max-Age", "600")
	headers.Add("Vary", "Origin")
	headers.Add("Vary", "Access-Control-Request-Method")
	headers.Add("Vary", "Access-Control-Request-Headers")
}

func (s *Server) writeJSONError(
	w http.ResponseWriter,
	requestID any,
	statusCode int,
	code int,
	message string,
) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(statusCode)
	_ = json.NewEncoder(w).Encode(shared.ErrorEnvelope(requestID, code, message))
}
