package gatewayruntime

import "time"

const (
	defaultProtocolVersion = 3
	defaultReconnectDelay  = 2 * time.Second
	defaultConnectTimeout  = 10 * time.Second
	defaultChallengeWait   = 2 * time.Second
	defaultRequestTimeout  = 15 * time.Second
)

var defaultOperatorScopes = []string{
	"operator.admin",
	"operator.read",
	"operator.write",
	"operator.approvals",
	"operator.pairing",
}

type Endpoint struct {
	Host string
	Port int
	TLS  bool
}

type PackageInfo struct {
	AppName     string
	PackageName string
	Version     string
	BuildNumber string
}

type DeviceInfo struct {
	Platform        string
	PlatformVersion string
	DeviceFamily    string
	ModelIdentifier string
}

func (d DeviceInfo) PlatformLabel() string {
	if d.PlatformVersion == "" {
		return d.Platform
	}
	return d.Platform + " " + d.PlatformVersion
}

type DeviceIdentity struct {
	DeviceID            string
	PublicKeyBase64URL  string
	PrivateKeyBase64URL string
}

type AuthConfig struct {
	Token       string
	DeviceToken string
	Password    string
}

type ConnectRequest struct {
	RuntimeID          string
	Mode               string
	ClientID           string
	Locale             string
	UserAgent          string
	Endpoint           Endpoint
	ConnectAuthMode    string
	ConnectAuthFields  []string
	ConnectAuthSources []string
	HasSharedAuth      bool
	HasDeviceToken     bool
	PackageInfo        PackageInfo
	DeviceInfo         DeviceInfo
	Identity           DeviceIdentity
	Auth               AuthConfig
}

type ConnectResult struct {
	OK                  bool
	Snapshot            map[string]any
	Auth                map[string]any
	ReturnedDeviceToken string
	Error               map[string]any
}

type RequestResult struct {
	OK      bool
	Payload any
	Error   map[string]any
}

type GatewayError struct {
	Message string
	Code    string
	Details map[string]any
}

func (e *GatewayError) Error() string {
	if e == nil {
		return ""
	}
	return e.Message
}

func (e *GatewayError) DetailCode() string {
	if e == nil || e.Details == nil {
		return ""
	}
	if value, ok := e.Details["code"].(string); ok {
		return value
	}
	return ""
}

func (e *GatewayError) Map() map[string]any {
	if e == nil {
		return map[string]any{}
	}
	payload := map[string]any{
		"message": e.Message,
	}
	if e.Code != "" {
		payload["code"] = e.Code
	}
	if len(e.Details) > 0 {
		payload["details"] = e.Details
	}
	return payload
}
