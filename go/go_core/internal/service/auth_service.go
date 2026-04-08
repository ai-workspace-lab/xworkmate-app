package service

import (
	"context"
	"errors"
	"strings"
)

var ErrInvalidCredentials = errors.New("invalid credentials")

type AuthRepository interface {
	Verify(ctx context.Context, username, password string) (bool, error)
}

type AuthService struct {
	repo AuthRepository
}

func NewAuthService(repo AuthRepository) *AuthService {
	return &AuthService{repo: repo}
}

func (s *AuthService) Authenticate(ctx context.Context, username, password string) error {
	username = strings.TrimSpace(username)
	password = strings.TrimSpace(password)
	if username == "" || password == "" {
		return ErrInvalidCredentials
	}
	ok, err := s.repo.Verify(ctx, username, password)
	if err != nil {
		return err
	}
	if !ok {
		return ErrInvalidCredentials
	}
	return nil
}
