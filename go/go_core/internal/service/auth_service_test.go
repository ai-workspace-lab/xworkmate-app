package service

import (
	"context"
	"errors"
	"testing"
)

type fakeAuthRepo struct {
	verify func(ctx context.Context, username, password string) (bool, error)
}

func (f fakeAuthRepo) Verify(ctx context.Context, username, password string) (bool, error) {
	return f.verify(ctx, username, password)
}

func TestAuthenticateRejectsBlankValues(t *testing.T) {
	svc := NewAuthService(fakeAuthRepo{
		verify: func(ctx context.Context, username, password string) (bool, error) {
			return true, nil
		},
	})

	if err := svc.Authenticate(context.Background(), " ", "secret"); !errors.Is(err, ErrInvalidCredentials) {
		t.Fatalf("expected invalid credentials, got %v", err)
	}
}

func TestAuthenticateRejectsFailedVerification(t *testing.T) {
	svc := NewAuthService(fakeAuthRepo{
		verify: func(ctx context.Context, username, password string) (bool, error) {
			if username != "alice" || password != "secret" {
				t.Fatalf("unexpected credentials: %q %q", username, password)
			}
			return false, nil
		},
	})

	if err := svc.Authenticate(context.Background(), "alice", "secret"); !errors.Is(err, ErrInvalidCredentials) {
		t.Fatalf("expected invalid credentials, got %v", err)
	}
}

func TestAuthenticateReturnsRepoError(t *testing.T) {
	wanted := errors.New("boom")
	svc := NewAuthService(fakeAuthRepo{
		verify: func(ctx context.Context, username, password string) (bool, error) {
			return false, wanted
		},
	})

	if err := svc.Authenticate(context.Background(), "alice", "secret"); !errors.Is(err, wanted) {
		t.Fatalf("expected repo error, got %v", err)
	}
}
