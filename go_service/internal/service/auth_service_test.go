package service

import "testing"

func TestAuthServiceValidateToken(t *testing.T) {
	svc := NewAuthService("secret")
	if !svc.ValidateToken("secret") {
		t.Fatal("expected valid token")
	}
	if svc.ValidateToken("wrong") {
		t.Fatal("expected invalid token")
	}
}
