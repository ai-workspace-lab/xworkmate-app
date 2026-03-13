//! FFI bindings for Codex CLI integration.
//!
//! This crate provides C-compatible FFI bindings for embedding Codex CLI
//! into Flutter applications.

mod runtime;
mod error;
mod types;

pub use error::CodexError;
pub use runtime::{CodexRuntime, CodexConfig, CodexConfigRust, ThreadHandle, RuntimeState};
pub use types::{CodexResult, CodexMessage, CodexEvent};

use std::ffi::{CStr, CString};
use std::os::raw::c_char;

/// FFI-exported initialization function.
/// 
/// # Safety
/// Must be called before any other FFI functions.
#[no_mangle]
pub unsafe extern "C" fn codex_init() -> i32 {
    0 // Success
}

/// FFI-exported runtime creation.
/// 
/// # Safety
/// Returns a pointer to the runtime. Caller must ensure thread safety.
#[no_mangle]
pub unsafe extern "C" fn codex_runtime_create(config: *const CodexConfig) -> *mut CodexRuntime {
    if config.is_null() {
        return std::ptr::null_mut();
    }
    
    let config = &*config;
    let runtime = Box::new(CodexRuntime::new(config.clone()));
    Box::into_raw(runtime)
}

/// FFI-exported runtime destruction.
/// 
/// # Safety
/// Must be called with a valid pointer from `codex_runtime_create`.
#[no_mangle]
pub unsafe extern "C" fn codex_runtime_destroy(runtime: *mut CodexRuntime) {
    if !runtime.is_null() {
        drop(Box::from_raw(runtime));
    }
}

/// FFI-exported start thread function.
/// 
/// # Safety
/// Must be called with valid pointers.
#[no_mangle]
pub unsafe extern "C" fn codex_start_thread(
    runtime: *mut CodexRuntime,
    cwd: *const c_char,
) -> ThreadHandle {
    if runtime.is_null() || cwd.is_null() {
        return ThreadHandle::null();
    }
    
    let _runtime = &mut *runtime;
    let _cwd = CStr::from_ptr(cwd);
    
    ThreadHandle::new(0)
}

/// FFI-exported send message function.
/// 
/// # Safety
/// Must be called with valid pointers.
#[no_mangle]
pub unsafe extern "C" fn codex_send_message(
    runtime: *mut CodexRuntime,
    thread: ThreadHandle,
    message: *const c_char,
) -> i32 {
    if runtime.is_null() || message.is_null() {
        return -1;
    }
    
    let _runtime = &mut *runtime;
    let _message = CStr::from_ptr(message);
    
    // TODO: Implement async message sending
    0
}

/// FFI-exported poll events function.
/// 
/// # Safety
/// Must be called with valid pointers.
#[no_mangle]
pub unsafe extern "C" fn codex_poll_events(
    runtime: *mut CodexRuntime,
    events: *mut CodexEvent,
    max_events: usize,
) -> usize {
    if runtime.is_null() || events.is_null() {
        return 0;
    }
    
    let _runtime = &mut *runtime;
    let _events = std::slice::from_raw_parts_mut(events, max_events);
    
    // TODO: Implement event polling
    0
}

/// FFI-exported shutdown function.
/// 
/// # Safety
/// Must be called with a valid runtime pointer.
#[no_mangle]
pub unsafe extern "C" fn codex_shutdown(runtime: *mut CodexRuntime) -> i32 {
    if runtime.is_null() {
        return -1;
    }
    
    let _runtime = &mut *runtime;
    // TODO: Implement graceful shutdown
    0
}

/// Get the last error message.
/// 
/// # Safety
/// Returns a pointer to static memory that is valid until the next FFI call.
#[no_mangle]
pub unsafe extern "C" fn codex_last_error(runtime: *mut CodexRuntime) -> *const c_char {
    if runtime.is_null() {
        return std::ptr::null();
    }
    
    let runtime = &mut *runtime;
    runtime.last_error.as_ptr()
}
