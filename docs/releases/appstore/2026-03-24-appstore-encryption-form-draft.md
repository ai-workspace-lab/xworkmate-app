# App Store Encryption Form Draft

Date: 2026-03-24
App: XWorkmate
Use case: App Store Connect "App Encryption Documentation" form drafting aid

This document is a practical filling guide for the App Store Connect encryption form. It is based on the current codebase behavior and is intended as submission support text, not legal advice.

## Recommended Selection Summary

- Encryption algorithm type:
  - Select: `代替在 Apple 操作系统中使用或访问加密，或与这些操作同时使用的标准加密算法`
  - English meaning: standard cryptographic algorithms used in addition to or alongside Apple operating system encryption
- `ITSAppUsesNonExemptEncryption`:
  - Set to: `NO`
- France distribution:
  - If France is included in sales regions, select: `是 / Yes`

## Page 1

### Field: App 用途

#### Chinese

XWorkmate 是一款 AI 工作台应用，用于连接用户配置的网关、模型接口和本地或远程协作服务。应用支持任务对话、文件附件、设备身份认证、安全连接和敏感凭据保护，帮助用户在桌面和移动端完成 AI 协作与工作流处理。

#### English

XWorkmate is an AI workspace application that connects to user-configured gateways, model endpoints, and local or remote collaboration services. The app supports task conversations, file attachments, device identity authentication, secure connections, and protection of sensitive credentials for AI collaboration and workflow execution across desktop and mobile devices.

### Field: App 用途精简版

#### Chinese

XWorkmate 是一款 AI 工作台应用，用于连接用户配置的网关、模型接口及本地或远程协作服务，提供任务对话、文件附件、安全连接、设备认证和凭据保护能力。

#### English

XWorkmate is an AI workspace application that connects to user-configured gateways, model endpoints, and local or remote collaboration services, providing task conversations, file attachments, secure connectivity, device authentication, and credential protection.

## Page 2

### Field: 加密功能说明

#### Chinese

本应用使用标准加密算法和安全机制，包括 HTTPS/WSS(TLS) 安全传输、Ed25519 设备身份密钥生成与数字签名，以及 SHA-256 摘要计算。上述能力用于设备身份认证、与用户配置服务的安全通信和敏感凭据保护。

#### English

This app uses standard cryptographic algorithms and security mechanisms, including HTTPS/WSS (TLS) secure transport, Ed25519 device identity key generation and digital signatures, and SHA-256 hashing. These capabilities are used for device identity authentication, secure communication with user-configured services, and protection of sensitive credentials.

### Field: 是否使用专有或自定义加密算法

#### Chinese

否。本应用不实现专有或自定义加密算法，仅使用标准加密算法和标准安全传输机制。

#### English

No. This app does not implement proprietary or custom encryption algorithms. It uses only standard cryptographic algorithms and standard secure transport mechanisms.

### Field: 是否只依赖 Apple 操作系统自带加密

#### Chinese

否。除 Apple 操作系统提供的安全传输能力外，本应用还使用标准密码学能力，例如 Ed25519 数字签名和 SHA-256 摘要。

#### English

No. In addition to Apple operating system transport security, the app also uses standard cryptographic functionality such as Ed25519 digital signatures and SHA-256 hashing.

## Page 3

### Field: 提交说明 / 附加说明

#### Chinese

本应用的加密用途主要限于设备身份认证、与用户配置服务的安全传输、认证载荷签名以及敏感凭据保护。本应用不提供面向用户的通用加密工具功能，也不包含专有或自定义加密算法。

#### English

The app's use of encryption is limited to device identity authentication, secure transport to user-configured services, authentication payload signing, and protection of sensitive credentials. The app does not provide general-purpose encryption functionality to end users and does not include proprietary or custom cryptographic algorithms.

### Field: 简短提交版

#### Chinese

本应用使用标准加密算法和安全传输协议，包括 HTTPS/WSS(TLS)、Ed25519 数字签名和 SHA-256 摘要，用于设备身份认证、安全通信和敏感凭据保护，不包含专有或自定义加密算法。

#### English

This app uses standard cryptographic algorithms and secure transport protocols, including HTTPS/WSS (TLS), Ed25519 digital signatures, and SHA-256 hashing, for device identity authentication, secure communication, and protection of sensitive credentials, and does not include proprietary or custom encryption algorithms.

## Notes

- If App Store Connect asks whether the app will be distributed in France and France is part of the release territory, select `是 / Yes`.
- If Apple asks for supporting documentation, start from this wording but adapt it to the exact submission screen and any legal or compliance advice you receive.
- Current implementation references:
  - [`lib/runtime/device_identity_store.dart`](/Users/shenlan/workspaces/cloud-neutral-toolkit/XWorkmate.svc.plus/lib/runtime/device_identity_store.dart)
  - [`lib/runtime/gateway_runtime.dart`](/Users/shenlan/workspaces/cloud-neutral-toolkit/XWorkmate.svc.plus/lib/runtime/gateway_runtime.dart)
  - [`lib/runtime/runtime_bootstrap.dart`](/Users/shenlan/workspaces/cloud-neutral-toolkit/XWorkmate.svc.plus/lib/runtime/runtime_bootstrap.dart)
  - [`lib/runtime/secure_config_store.dart`](/Users/shenlan/workspaces/cloud-neutral-toolkit/XWorkmate.svc.plus/lib/runtime/secure_config_store.dart)
  - [`lib/runtime/secret_store.dart`](/Users/shenlan/workspaces/cloud-neutral-toolkit/XWorkmate.svc.plus/lib/runtime/secret_store.dart)
