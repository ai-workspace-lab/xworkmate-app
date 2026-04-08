package handler

import (
	"encoding/json"
	"net/http"

	"xworkmate/go_service/internal/service"
)

type AuthHandler struct {
	service *service.AuthService
}

func NewAuthHandler(service *service.AuthService) *AuthHandler {
	return &AuthHandler{service: service}
}

func (h *AuthHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if h.service == nil {
		http.Error(w, "service unavailable", http.StatusServiceUnavailable)
		return
	}
	token := r.Header.Get("Authorization")
	if !h.service.ValidateToken(token) {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	_ = json.NewEncoder(w).Encode(map[string]any{"ok": true})
}
