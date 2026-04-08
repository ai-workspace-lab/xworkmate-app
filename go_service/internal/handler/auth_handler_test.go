package handler

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"xworkmate/go_service/internal/service"
)

func TestAuthHandlerServeHTTP(t *testing.T) {
	h := NewAuthHandler(service.NewAuthService("secret"))
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.Header.Set("Authorization", "secret")
	rr := httptest.NewRecorder()

	h.ServeHTTP(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rr.Code)
	}
}
