package service

import "strings"

type AuthService struct {
	expectedToken string
}

func NewAuthService(expectedToken string) *AuthService {
	return &AuthService{expectedToken: strings.TrimSpace(expectedToken)}
}

func (s *AuthService) ValidateToken(token string) bool {
	return strings.TrimSpace(token) != "" && strings.TrimSpace(token) == s.expectedToken
}
