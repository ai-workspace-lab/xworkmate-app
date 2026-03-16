//! Core runtime for Codex FFI.

use std::ffi::CString;
use std::os::raw::c_char;
use std::path::PathBuf;

use crate::error::CodexError;

/// Configuration for Codex runtime.
#[derive(Debug, Clone)]
#[repr(C)]
pub struct CodexConfig {
    /// Path to Codex binary.
    pub codex_path: *const c_char,
    /// Working directory.
    pub working_directory: *const c_char,
    /// Sandbox mode: 0=read-only, 1=workspace-write, 2=danger-full-access.
    pub sandbox_mode: i32,
    /// Approval policy: 0=suggest, 1=auto-edit, 2=full-auto.
    pub approval_policy: i32,
    /// Model to use.
    pub model: *const c_char,
    /// API key for gateway.
    pub api_key: *const c_char,
    /// Gateway URL.
    pub gateway_url: *const c_char,
    /// Enable debug logging.
    pub debug: bool,
}

impl Default for CodexConfig {
    fn default() -> Self {
        CodexConfig {
            codex_path: std::ptr::null(),
            working_directory: std::ptr::null(),
            sandbox_mode: 1, // workspace-write
            approval_policy: 0, // suggest
            model: std::ptr::null(),
            api_key: std::ptr::null(),
            gateway_url: std::ptr::null(),
            debug: false,
        }
    }
}

impl CodexConfig {
    /// Convert FFI config to Rust types.
    pub unsafe fn to_rust(&self) -> Result<CodexConfigRust, CodexError> {
        let codex_path = if self.codex_path.is_null() {
            None
        } else {
            Some(std::ffi::CStr::from_ptr(self.codex_path)
                .to_string_lossy()
                .into_owned())
        };

        let working_directory = if self.working_directory.is_null() {
            None
        } else {
            Some(std::ffi::CStr::from_ptr(self.working_directory)
                .to_string_lossy()
                .into_owned())
        };

        let model = if self.model.is_null() {
            None
        } else {
            Some(std::ffi::CStr::from_ptr(self.model)
                .to_string_lossy()
                .into_owned())
        };

        let api_key = if self.api_key.is_null() {
            None
        } else {
            Some(std::ffi::CStr::from_ptr(self.api_key)
                .to_string_lossy()
                .into_owned())
        };

        let gateway_url = if self.gateway_url.is_null() {
            None
        } else {
            Some(std::ffi::CStr::from_ptr(self.gateway_url)
                .to_string_lossy()
                .into_owned())
        };

        Ok(CodexConfigRust {
            codex_path,
            working_directory,
            sandbox_mode: self.sandbox_mode,
            approval_policy: self.approval_policy,
            model,
            api_key,
            gateway_url,
            debug: self.debug,
        })
    }
}

/// Rust-native config type.
#[derive(Debug, Clone, Default)]
pub struct CodexConfigRust {
    pub codex_path: Option<String>,
    pub working_directory: Option<String>,
    pub sandbox_mode: i32,
    pub approval_policy: i32,
    pub model: Option<String>,
    pub api_key: Option<String>,
    pub gateway_url: Option<String>,
    pub debug: bool,
}

/// Opaque handle to a thread.
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct ThreadHandle {
    pub id: u64,
}

impl ThreadHandle {
    pub fn new(id: u64) -> Self {
        ThreadHandle { id }
    }

    pub fn null() -> Self {
        ThreadHandle { id: 0 }
    }

    pub fn is_null(&self) -> bool {
        self.id == 0
    }
}

/// Codex runtime state.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RuntimeState {
    Disconnected,
    Connecting,
    Connected,
    Ready,
    Error,
}

/// Core runtime for managing Codex process.
pub struct CodexRuntime {
    config: CodexConfigRust,
    state: RuntimeState,
    pub last_error: CString,
}

impl CodexRuntime {
    /// Create a new runtime with the given configuration.
    pub fn new(config: CodexConfig) -> Self {
        let rust_config = unsafe { config.to_rust().unwrap_or_default() };
        CodexRuntime {
            config: rust_config,
            state: RuntimeState::Disconnected,
            last_error: CString::new("").unwrap_or_default(),
        }
    }

    /// Create from Rust config.
    pub fn with_config(config: CodexConfigRust) -> Self {
        CodexRuntime {
            config,
            state: RuntimeState::Disconnected,
            last_error: CString::new("").unwrap_or_default(),
        }
    }

    /// Get the current state.
    pub fn state(&self) -> RuntimeState {
        self.state
    }

    /// Set error message.
    pub fn set_error(&mut self, message: &str) {
        self.last_error = CString::new(message).unwrap_or_default();
        self.state = RuntimeState::Error;
    }

    /// Find the Codex binary.
    pub fn find_codex_binary(&self) -> Option<PathBuf> {
        // Check config path
        if let Some(ref path) = self.config.codex_path {
            let path = PathBuf::from(path);
            if path.exists() {
                return Some(path);
            }
        }

        // Check environment
        if let Ok(path) = std::env::var("CODEX_PATH") {
            let path = PathBuf::from(path);
            if path.exists() {
                return Some(path);
            }
        }

        // Check common locations
        let home = std::env::var("HOME").unwrap_or_default();
        let cargo_path = format!("{}/.cargo/bin/codex", home);
        let local_path = format!("{}/.local/bin/codex", home);
        let paths = [
            "/usr/local/bin/codex",
            "/opt/homebrew/bin/codex",
            cargo_path.as_str(),
            local_path.as_str(),
        ];

        for path in paths {
            let path = PathBuf::from(path);
            if path.exists() {
                return Some(path);
            }
        }

        None
    }

    /// Start the runtime.
    pub async fn start(&mut self) -> Result<(), CodexError> {
        if self.state == RuntimeState::Ready {
            return Err(CodexError::AlreadyInitialized);
        }

        self.state = RuntimeState::Connecting;
        
        // Find binary
        let _binary = self.find_codex_binary()
            .ok_or_else(|| CodexError::Process("Codex binary not found".into()))?;

        // TODO: Start process
        self.state = RuntimeState::Ready;
        
        Ok(())
    }

    /// Stop the runtime.
    pub async fn stop(&mut self) -> Result<(), CodexError> {
        if self.state == RuntimeState::Disconnected {
            return Ok(());
        }

        // TODO: Stop process
        self.state = RuntimeState::Disconnected;
        
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_config_default() {
        let config = CodexConfig::default();
        assert!(config.codex_path.is_null());
        assert_eq!(config.sandbox_mode, 1);
    }

    #[test]
    fn test_thread_handle() {
        let handle = ThreadHandle::new(42);
        assert_eq!(handle.id, 42);
        assert!(!handle.is_null());

        let null_handle = ThreadHandle::null();
        assert!(null_handle.is_null());
    }

    #[test]
    fn test_runtime_state() {
        let config = CodexConfigRust {
            codex_path: None,
            working_directory: None,
            sandbox_mode: 1,
            approval_policy: 0,
            model: None,
            api_key: None,
            gateway_url: None,
            debug: false,
        };

        let runtime = CodexRuntime::with_config(config);
        assert_eq!(runtime.state(), RuntimeState::Disconnected);
    }
}
