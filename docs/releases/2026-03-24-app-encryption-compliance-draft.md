# XWorkmate App Encryption Compliance Draft

Date: 2026-03-24
App: XWorkmate
Platforms: iOS, macOS
Related setting: `ITSAppUsesNonExemptEncryption = YES`

## Purpose

This note is a practical drafting aid for App Store Connect export compliance and related distribution declarations. It summarizes the app's current encryption-related behavior based on the codebase. It is not legal advice and should be reviewed by the publisher before submission.

## Recommended App Store Connect Position

- The app should be treated as using encryption beyond a pure "Apple OS only" transport case.
- The safer declaration path is:
  - App uses standard encryption algorithms.
  - `ITSAppUsesNonExemptEncryption` remains `YES`.
- If the app is distributed in France, the publisher should assume the France-specific encryption documentation path applies unless counsel or a qualified compliance reviewer confirms otherwise.

## Implementation Basis

The current codebase uses encryption and cryptographic functions in these areas:

- Device identity generation and signing:
  - [`lib/runtime/device_identity_store.dart`](/Users/shenlan/workspaces/cloud-neutral-toolkit/XWorkmate.svc.plus/lib/runtime/device_identity_store.dart)
  - Uses `Ed25519` key generation and signing.
  - Uses `SHA-256` to derive a stable device identifier from the public key.
- Secure transport:
  - Gateway and relay flows use `https` / `wss` / TLS-enabled endpoints where configured.
  - Representative files:
    - [`lib/runtime/gateway_runtime.dart`](/Users/shenlan/workspaces/cloud-neutral-toolkit/XWorkmate.svc.plus/lib/runtime/gateway_runtime.dart)
    - [`lib/runtime/runtime_bootstrap.dart`](/Users/shenlan/workspaces/cloud-neutral-toolkit/XWorkmate.svc.plus/lib/runtime/runtime_bootstrap.dart)
    - [`lib/web/web_relay_gateway_client.dart`](/Users/shenlan/workspaces/cloud-neutral-toolkit/XWorkmate.svc.plus/lib/web/web_relay_gateway_client.dart)
- Secure storage:
  - Secrets such as tokens and passwords are persisted via platform secure storage abstractions rather than plain preferences.
  - Representative files:
    - [`lib/runtime/secure_config_store.dart`](/Users/shenlan/workspaces/cloud-neutral-toolkit/XWorkmate.svc.plus/lib/runtime/secure_config_store.dart)
    - [`lib/runtime/secret_store.dart`](/Users/shenlan/workspaces/cloud-neutral-toolkit/XWorkmate.svc.plus/lib/runtime/secret_store.dart)

## Chinese Draft

### 用途说明

XWorkmate 是一个 AI 工作台客户端，用于连接用户配置的网关、模型接口和本地/远程协作能力。应用会在用户发起连接、认证或协作请求时使用加密相关能力。

### 加密功能说明

本应用使用行业标准加密算法和相关安全机制，主要包括：

- 使用标准安全传输协议与用户配置的服务端通信，例如 HTTPS 和 WSS/TLS。
- 使用 Ed25519 生成设备身份密钥对，并对认证载荷进行签名，用于设备身份识别与认证流程。
- 使用 SHA-256 从公开密钥派生稳定设备标识。
- 使用平台安全存储能力保存令牌、密码和其他敏感凭据。

### 不包含的情况

本应用当前未实现自研或专有加密算法。当前使用的是标准算法和标准安全传输机制。

### 提交时可用简述

本应用使用标准加密算法和安全传输协议，包括 HTTPS/WSS(TLS)、Ed25519 数字签名以及 SHA-256 摘要，用于设备身份认证、与用户配置服务的安全通信以及敏感凭据保护。本应用不包含专有或自定义加密算法。

## English Draft

### Product description

XWorkmate is an AI workspace client that connects to user-configured gateways, model endpoints, and local or remote collaboration services. The app uses cryptographic functionality when the user initiates connection, authentication, or collaboration workflows.

### Encryption description

The app uses standard cryptographic algorithms and security mechanisms, including:

- Standard secure transport protocols for communication with user-configured services, such as HTTPS and WSS/TLS.
- Ed25519 key generation and digital signatures for device identity and authentication payload signing.
- SHA-256 hashing to derive a stable device identifier from the public key.
- Platform secure storage mechanisms to protect tokens, passwords, and other sensitive credentials.

### Exclusions

The app does not implement proprietary or custom encryption algorithms. The current implementation relies on standard cryptographic algorithms and standard secure transport mechanisms.

### Short submission-ready wording

This app uses standard cryptographic algorithms and secure transport protocols, including HTTPS/WSS (TLS), Ed25519 digital signatures, and SHA-256 hashing, for device identity, authentication, secure communication with user-configured services, and protection of sensitive credentials. The app does not use proprietary or custom encryption algorithms.

## Files Updated

- [`ios/Runner/Info.plist`](/Users/shenlan/workspaces/cloud-neutral-toolkit/XWorkmate.svc.plus/ios/Runner/Info.plist)
- [`macos/Runner/Info.plist`](/Users/shenlan/workspaces/cloud-neutral-toolkit/XWorkmate.svc.plus/macos/Runner/Info.plist)

