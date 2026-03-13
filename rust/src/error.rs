//! Error types for Codex FFI.

use std::fmt;

/// Error type for Codex operations.
#[derive(Debug, Clone)]
pub enum CodexError {
    /// Invalid argument.
    InvalidArgument(String),
    /// Runtime not initialized.
    NotInitialized,
    /// Runtime already initialized.
    AlreadyInitialized,
    /// IO error.
    Io(String),
    /// JSON-RPC error.
    Rpc { code: i32, message: String },
    /// Timeout error.
    Timeout(String),
    /// Process error.
    Process(String),
    /// Thread error.
    Thread(String),
    /// Configuration error.
    Config(String),
    /// Unknown error.
    Unknown(String),
}

impl fmt::Display for CodexError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            CodexError::InvalidArgument(msg) => write!(f, "Invalid argument: {}", msg),
            CodexError::NotInitialized => write!(f, "Runtime not initialized"),
            CodexError::AlreadyInitialized => write!(f, "Runtime already initialized"),
            CodexError::Io(msg) => write!(f, "IO error: {}", msg),
            CodexError::Rpc { code, message } => write!(f, "RPC error ({}): {}", code, message),
            CodexError::Timeout(msg) => write!(f, "Timeout: {}", msg),
            CodexError::Process(msg) => write!(f, "Process error: {}", msg),
            CodexError::Thread(msg) => write!(f, "Thread error: {}", msg),
            CodexError::Config(msg) => write!(f, "Configuration error: {}", msg),
            CodexError::Unknown(msg) => write!(f, "Unknown error: {}", msg),
        }
    }
}

impl std::error::Error for CodexError {}

impl From<std::io::Error> for CodexError {
    fn from(err: std::io::Error) -> Self {
        CodexError::Io(err.to_string())
    }
}

impl From<serde_json::Error> for CodexError {
    fn from(err: serde_json::Error) -> Self {
        CodexError::Config(err.to_string())
    }
}
