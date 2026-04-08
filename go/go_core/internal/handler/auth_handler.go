package handler

import (
	"encoding/json"
	"net/http"

	"xworkmate/go_core/internal/service"
)

type Authenticator interface {
	Authenticate(username, password string) error
}

type AuthHandler struct {
	service Authenticator
}

func NewAuthHandler(svc Authenticator) *AuthHandler {
	return &AuthHandler{service: svc}
}

func NewServiceAdapter(svc *service.AuthService) Authenticator {
	return authServiceAdapter{service: svc}
}

func (h *AuthHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	var payload struct {
		Username string `json:"username"`
		Password string `json:"password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		http.Error(w, "invalid json", http.StatusBadRequest)
		return
	}
	if err := h.service.Authenticate(payload.Username, payload.Password); err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}

type authServiceAdapter struct {
	service *service.AuthService
}

func (a authServiceAdapter) Authenticate(username, password string) error {
	return a.service.Authenticate(nil, username, password)
}
