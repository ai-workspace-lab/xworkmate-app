package handler

import (
	"bytes"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
)

type fakeAuthenticator struct {
	err error
}

func (f fakeAuthenticator) Authenticate(username, password string) error {
	return f.err
}

func TestAuthHandlerRejectsInvalidJSON(t *testing.T) {
	handler := NewAuthHandler(fakeAuthenticator{})
	req := httptest.NewRequest(http.MethodPost, "/auth", bytes.NewBufferString("{"))
	rec := httptest.NewRecorder()

	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", rec.Code)
	}
}

func TestAuthHandlerReturnsUnauthorizedOnServiceFailure(t *testing.T) {
	handler := NewAuthHandler(fakeAuthenticator{err: errors.New("invalid credentials")})
	req := httptest.NewRequest(http.MethodPost, "/auth", bytes.NewBufferString(`{"username":"alice","password":"secret"}`))
	rec := httptest.NewRecorder()

	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", rec.Code)
	}
}

func TestAuthHandlerReturnsOKOnSuccess(t *testing.T) {
	handler := NewAuthHandler(fakeAuthenticator{})
	req := httptest.NewRequest(http.MethodPost, "/auth", bytes.NewBufferString(`{"username":"alice","password":"secret"}`))
	rec := httptest.NewRecorder()

	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
}
