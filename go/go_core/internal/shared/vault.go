package shared

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

type VaultKVResult struct {
	Operation string         `json:"operation"`
	Mount     string         `json:"mount"`
	Path      string         `json:"path"`
	Data      map[string]any `json:"data,omitempty"`
	Keys      []string       `json:"keys,omitempty"`
	Metadata  map[string]any `json:"metadata,omitempty"`
}

func HandleVaultKVTool(arguments map[string]any) (string, error) {
	request, err := buildVaultKVRequest(arguments)
	if err != nil {
		return "", err
	}
	result, err := executeVaultKVRequest(request)
	if err != nil {
		return "", err
	}
	encoded, err := json.MarshalIndent(result, "", "  ")
	if err != nil {
		return "", err
	}
	return string(encoded), nil
}

type vaultKVRequest struct {
	baseURL   string
	token     string
	namespace string
	operation string
	mount     string
	path      string
	data      map[string]any
	cas       int
}

func buildVaultKVRequest(arguments map[string]any) (vaultKVRequest, error) {
	baseURL := strings.TrimSpace(EnvOrDefault("VAULT_SERVER_URL", ""))
	if baseURL == "" {
		return vaultKVRequest{}, errors.New("VAULT_SERVER_URL environment variable not set")
	}
	token := strings.TrimSpace(EnvOrDefault("VAULT_SERVER_ROOT_ACCESS_TOKEN", ""))
	if token == "" {
		return vaultKVRequest{}, errors.New("VAULT_SERVER_ROOT_ACCESS_TOKEN environment variable not set")
	}
	operation := strings.ToLower(strings.TrimSpace(StringArg(arguments, "operation", "")))
	if operation == "" {
		return vaultKVRequest{}, errors.New("operation is required")
	}
	path := normalizeVaultPath(StringArg(arguments, "path", ""))
	if path == "" {
		return vaultKVRequest{}, errors.New("path is required")
	}
	data, err := vaultDataArg(arguments["data"])
	if err != nil {
		return vaultKVRequest{}, err
	}
	return vaultKVRequest{
		baseURL:   strings.TrimRight(baseURL, "/"),
		token:     token,
		namespace: strings.TrimSpace(EnvOrDefault("VAULT_NAMESPACE", "")),
		operation: operation,
		mount:     normalizeVaultMount(StringArg(arguments, "mount", "secret")),
		path:      path,
		data:      data,
		cas:       vaultCASArg(arguments["cas"]),
	}, nil
}

func executeVaultKVRequest(request vaultKVRequest) (VaultKVResult, error) {
	switch request.operation {
	case "get", "read":
		return vaultKVRead(request)
	case "put", "write":
		return vaultKVWrite(request)
	case "list":
		return vaultKVList(request)
	case "delete":
		return vaultKVDelete(request)
	default:
		return VaultKVResult{}, fmt.Errorf("unsupported operation: %s", request.operation)
	}
}

func vaultKVRead(request vaultKVRequest) (VaultKVResult, error) {
	response, err := doVaultRequest(
		request,
		http.MethodGet,
		vaultDataURL(request.mount, request.path),
		nil,
	)
	if err != nil {
		return VaultKVResult{}, err
	}
	dataBlock := mapArg(response["data"])
	return VaultKVResult{
		Operation: "read",
		Mount:     request.mount,
		Path:      request.path,
		Data:      mapArg(dataBlock["data"]),
		Metadata:  mapArg(dataBlock["metadata"]),
	}, nil
}

func vaultKVWrite(request vaultKVRequest) (VaultKVResult, error) {
	if len(request.data) == 0 {
		return VaultKVResult{}, errors.New("data is required for write operations")
	}
	payload := map[string]any{"data": request.data}
	if request.cas > 0 {
		payload["options"] = map[string]any{"cas": request.cas}
	}
	response, err := doVaultRequest(
		request,
		http.MethodPost,
		vaultDataURL(request.mount, request.path),
		payload,
	)
	if err != nil {
		return VaultKVResult{}, err
	}
	return VaultKVResult{
		Operation: "write",
		Mount:     request.mount,
		Path:      request.path,
		Data:      request.data,
		Metadata:  mapArg(mapArg(response["data"])["metadata"]),
	}, nil
}

func vaultKVList(request vaultKVRequest) (VaultKVResult, error) {
	response, err := doVaultRequest(
		request,
		"LIST",
		vaultMetadataURL(request.mount, request.path),
		nil,
	)
	if err != nil {
		return VaultKVResult{}, err
	}
	dataBlock := mapArg(response["data"])
	return VaultKVResult{
		Operation: "list",
		Mount:     request.mount,
		Path:      request.path,
		Keys:      stringSliceArg(dataBlock["keys"]),
	}, nil
}

func vaultKVDelete(request vaultKVRequest) (VaultKVResult, error) {
	_, err := doVaultRequest(
		request,
		http.MethodDelete,
		vaultDataURL(request.mount, request.path),
		nil,
	)
	if err != nil {
		return VaultKVResult{}, err
	}
	return VaultKVResult{
		Operation: "delete",
		Mount:     request.mount,
		Path:      request.path,
	}, nil
}

func doVaultRequest(
	request vaultKVRequest,
	method string,
	target string,
	payload map[string]any,
) (map[string]any, error) {
	var body io.Reader
	if payload != nil {
		encoded, err := json.Marshal(payload)
		if err != nil {
			return nil, err
		}
		body = bytes.NewReader(encoded)
	}
	httpRequest, err := http.NewRequest(method, target, body)
	if err != nil {
		return nil, err
	}
	httpRequest.Header.Set("X-Vault-Token", request.token)
	if request.namespace != "" {
		httpRequest.Header.Set("X-Vault-Namespace", request.namespace)
	}
	if payload != nil {
		httpRequest.Header.Set("Content-Type", "application/json")
	}
	client := &http.Client{Timeout: 30 * time.Second}
	response, err := client.Do(httpRequest)
	if err != nil {
		return nil, err
	}
	defer response.Body.Close()
	bodyBytes, err := io.ReadAll(response.Body)
	if err != nil {
		return nil, err
	}
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return nil, fmt.Errorf(
			"vault api error %d: %s",
			response.StatusCode,
			strings.TrimSpace(string(bodyBytes)),
		)
	}
	if len(strings.TrimSpace(string(bodyBytes))) == 0 {
		return map[string]any{}, nil
	}
	var decoded map[string]any
	if err := json.Unmarshal(bodyBytes, &decoded); err != nil {
		return nil, err
	}
	return decoded, nil
}

func vaultDataURL(mount, path string) string {
	return fmt.Sprintf("%s/data/%s", vaultBasePath(mount), vaultPathSegments(path))
}

func vaultMetadataURL(mount, path string) string {
	return fmt.Sprintf("%s/metadata/%s", vaultBasePath(mount), vaultPathSegments(path))
}

func vaultBasePath(mount string) string {
	return fmt.Sprintf("%s/v1/%s", strings.TrimRight(strings.TrimSpace(EnvOrDefault("VAULT_SERVER_URL", "")), "/"), url.PathEscape(normalizeVaultMount(mount)))
}

func vaultPathSegments(path string) string {
	segments := strings.Split(normalizeVaultPath(path), "/")
	for index, segment := range segments {
		segments[index] = url.PathEscape(segment)
	}
	return strings.Join(segments, "/")
}

func normalizeVaultMount(raw string) string {
	trimmed := strings.Trim(strings.TrimSpace(raw), "/")
	if trimmed == "" {
		return "secret"
	}
	return trimmed
}

func normalizeVaultPath(raw string) string {
	return strings.Trim(strings.TrimSpace(raw), "/")
}

func vaultDataArg(raw any) (map[string]any, error) {
	if raw == nil {
		return nil, nil
	}
	switch typed := raw.(type) {
	case map[string]any:
		return typed, nil
	case string:
		trimmed := strings.TrimSpace(typed)
		if trimmed == "" {
			return nil, nil
		}
		var decoded map[string]any
		if err := json.Unmarshal([]byte(trimmed), &decoded); err != nil {
			return nil, errors.New("data must be a JSON object")
		}
		return decoded, nil
	default:
		return nil, errors.New("data must be an object")
	}
}

func vaultCASArg(raw any) int {
	switch typed := raw.(type) {
	case int:
		return typed
	case int64:
		return int(typed)
	case float64:
		return int(typed)
	case string:
		return IntArg(typed, 0)
	default:
		return 0
	}
}

func mapArg(raw any) map[string]any {
	switch typed := raw.(type) {
	case map[string]any:
		return typed
	default:
		return map[string]any{}
	}
}

func stringSliceArg(raw any) []string {
	values, ok := raw.([]any)
	if !ok {
		return nil
	}
	result := make([]string, 0, len(values))
	for _, value := range values {
		text := strings.TrimSpace(fmt.Sprint(value))
		if text == "" || text == "<nil>" {
			continue
		}
		result = append(result, text)
	}
	return result
}
