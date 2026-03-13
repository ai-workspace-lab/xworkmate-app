//! FFI-safe types for Codex integration.

use std::ffi::CString;
use std::os::raw::c_char;

/// FFI-safe result type.
#[repr(C)]
pub struct CodexResult {
    /// Whether the operation was successful.
    pub success: bool,
    /// Error code if failed.
    pub error_code: i32,
    /// Error message if failed.
    pub error_message: *const c_char,
}

impl CodexResult {
    pub fn ok() -> Self {
        CodexResult {
            success: true,
            error_code: 0,
            error_message: std::ptr::null(),
        }
    }

    pub fn err(code: i32, message: &str) -> Self {
        let c_message = CString::new(message).unwrap_or_default();
        CodexResult {
            success: false,
            error_code: code,
            error_message: c_message.as_ptr(),
        }
    }
}

/// FFI-safe message type.
#[repr(C)]
pub struct CodexMessage {
    /// Message type (text, code, tool_call, etc.).
    pub message_type: *const c_char,
    /// Message content.
    pub content: *const c_char,
    /// Thread ID.
    pub thread_id: *const c_char,
    /// Turn ID.
    pub turn_id: *const c_char,
}

/// FFI-safe event type.
#[repr(C)]
pub struct CodexEvent {
    /// Event type (started, delta, completed, error).
    pub event_type: *const c_char,
    /// Thread ID.
    pub thread_id: *const c_char,
    /// Turn ID.
    pub turn_id: *const c_char,
    /// Event data as JSON.
    pub data: *const c_char,
    /// Timestamp (Unix millis).
    pub timestamp: i64,
}

/// FFI-safe model info.
#[repr(C)]
pub struct CodexModelInfo {
    /// Model ID.
    pub id: *const c_char,
    /// Model name.
    pub name: *const c_char,
    /// Provider name.
    pub provider: *const c_char,
    /// Is online.
    pub is_online: bool,
}

/// FFI-safe account info.
#[repr(C)]
pub struct CodexAccountInfo {
    /// Email.
    pub email: *const c_char,
    /// Plan type.
    pub plan: *const c_char,
    /// Has credits.
    pub has_credits: bool,
    /// Credits balance.
    pub credits_balance: f64,
    /// Rate limits JSON.
    pub rate_limits: *const c_char,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_result_ok() {
        let result = CodexResult::ok();
        assert!(result.success);
        assert_eq!(result.error_code, 0);
    }

    #[test]
    fn test_result_err() {
        let result = CodexResult::err(1, "test error");
        assert!(!result.success);
        assert_eq!(result.error_code, 1);
    }
}
