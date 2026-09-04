#ifndef TSUBAME_H
#define TSUBAME_H
#include "tsubame_types.h"

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
TSUBAME_API uint32_t tsubame_abi_version(void);

/* Inputs are borrowed only during the call. All output pointers are required.
 * Output slots are cleared before validation and must not hold owned objects.
 * Errors own their strings; use tsubame_error_free, not the system allocator. */
TSUBAME_API TsubameStatus tsubame_engine_create(
    const uint8_t *database_path, size_t database_path_length,
    TsubameEngine **out_engine, TsubameError *out_error);
TSUBAME_API void tsubame_engine_destroy(TsubameEngine *engine);

/* Offsets are half-open original UTF-8 byte offsets on Character boundaries.
 * Calls on an engine are serialized. Destroy must not race with calls using it.
 * On success the caller owns *out_result; on failure it is NULL. */
TSUBAME_API TsubameStatus tsubame_lookup(
    TsubameEngine *engine, const uint8_t *text, size_t text_length,
    size_t position, size_t result_limit,
    TsubameResult **out_result, TsubameError *out_error);
TSUBAME_API TsubameStatus tsubame_scan(
    TsubameEngine *engine, const uint8_t *text, size_t text_length,
    size_t start, size_t end, size_t group_limit, size_t entries_per_group_limit,
    TsubameResult **out_result, TsubameError *out_error);

/* The view and all nested pointers are immutable and borrowed until result
 * destruction. They survive subsequent queries and engine destruction.
 * NULL is accepted by destroy. Each non-NULL result must be destroyed once. */
TSUBAME_API TsubameStatus tsubame_result_get_view(
    const TsubameResult *result, TsubameResultView *out_view);
TSUBAME_API void tsubame_result_destroy(TsubameResult *result);

/* Lazily materializes and caches typed structured content. Concurrent reads
 * are supported. The returned value is borrowed until its RESULT is destroyed.
 * Only the union field selected by kind is valid. Object keys are sorted.
 * Result destruction must not race with any view/content access. */
TSUBAME_API TsubameStatus tsubame_content_get(
    const TsubameContent *content, const TsubameValue **out_value,
    TsubameError *out_error);

/* Frees diagnostic strings and clears the struct. NULL and {0} are accepted. */
TSUBAME_API void tsubame_error_free(TsubameError *error);

#ifdef __cplusplus
}
#endif
#endif
