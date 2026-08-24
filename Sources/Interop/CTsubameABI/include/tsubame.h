#ifndef TSUBAME_H
#define TSUBAME_H

#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
#  if defined(TSUBAME_ABI_BUILDING)
#    define TSUBAME_API __declspec(dllexport)
#  else
#    define TSUBAME_API __declspec(dllimport)
#  endif
#elif defined(__GNUC__) || defined(__clang__)
#  define TSUBAME_API __attribute__((visibility("default")))
#else
#  define TSUBAME_API
#endif

#ifdef __cplusplus
extern "C" {
#endif

#define TSUBAME_ABI_VERSION 1u
#define TSUBAME_SERIALIZATION_JSON_V1 1u

typedef struct TsubameEngine TsubameEngine;

typedef struct TsubameBuffer {
    uint8_t *data;
    size_t length;
} TsubameBuffer;

typedef int32_t TsubameStatus;

enum {
    TSUBAME_STATUS_OK = 0,
    TSUBAME_STATUS_INVALID_ARGUMENT = 1,
    TSUBAME_STATUS_INVALID_UTF8 = 2,
    TSUBAME_STATUS_INVALID_JSON = 3,
    TSUBAME_STATUS_UNSUPPORTED = 4,
    TSUBAME_STATUS_INVALID_REQUEST = 5,
    TSUBAME_STATUS_ENGINE_OPEN_FAILED = 6,
    TSUBAME_STATUS_EXECUTION_FAILED = 7,
    TSUBAME_STATUS_RESULT_TOO_LARGE = 8,
    TSUBAME_STATUS_INTERNAL_ERROR = 255
};

/* Returns the ABI version implemented by this library. */
TSUBAME_API uint32_t
tsubame_abi_version(void);

/*
 * Opens one dictionary.sqlite. The path is UTF-8. The caller owns the input;
 * Core copies it before this call returns and never retains the pointer. A NULL
 * input pointer is valid only when its length is zero.
 *
 * On success, *out_engine is non-NULL and *out_error is empty. On failure,
 * *out_engine is NULL and *out_error may contain a UTF-8 JSON error envelope.
 * Release that buffer with tsubame_buffer_free.
 */
TSUBAME_API TsubameStatus
tsubame_engine_create(
    const uint8_t *database_path,
    size_t database_path_length,
    TsubameEngine **out_engine,
    TsubameBuffer *out_error
);

/*
 * Releases an engine. NULL is accepted. Destroy must not race with execute
 * calls that use the same handle.
 */
TSUBAME_API void
tsubame_engine_destroy(TsubameEngine *engine);

/*
 * Executes one JSON request. The caller owns the input; Core copies it during
 * the call. A NULL input pointer is valid only when its length is zero. ABI v1
 * supports TSUBAME_SERIALIZATION_JSON_V1. Concurrent calls on one engine are
 * supported and serialized by Core.
 *
 * out_result and out_error must be distinct non-NULL pointers. Exactly one is
 * normally populated. Release either allocation with tsubame_buffer_free.
 * Returned JSON is UTF-8 and is not NUL-terminated.
 */
TSUBAME_API TsubameStatus
tsubame_engine_execute(
    TsubameEngine *engine,
    uint32_t serialization,
    const uint8_t *request,
    size_t request_length,
    TsubameBuffer *out_result,
    TsubameBuffer *out_error
);

/* Releases a Core-owned output buffer, then resets it to {NULL, 0}. */
TSUBAME_API void
tsubame_buffer_free(TsubameBuffer *buffer);

#ifdef __cplusplus
}
#endif

#endif
