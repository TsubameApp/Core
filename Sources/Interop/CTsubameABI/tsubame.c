#include "tsubame.h"

/* Swift bridge uses raw handles; public callers use the typed opaque handles. */
extern uint32_t tsubame_swift_abi_version(void);
extern TsubameStatus tsubame_swift_engine_create(
    const uint8_t *, size_t, void **, TsubameError *);
extern void tsubame_swift_engine_destroy(void *);
extern TsubameStatus tsubame_swift_lookup(
    void *, const uint8_t *, size_t, size_t, size_t, void **, TsubameError *);
extern TsubameStatus tsubame_swift_scan(
    void *, const uint8_t *, size_t, size_t, size_t, size_t, size_t,
    void **, TsubameError *);
extern TsubameStatus tsubame_swift_result_get_view(const void *, TsubameResultView *);
extern void tsubame_swift_result_destroy(void *);
extern TsubameStatus tsubame_swift_content_get(
    const void *, const TsubameValue **, TsubameError *);
extern void tsubame_swift_error_free(TsubameError *);

uint32_t tsubame_abi_version(void) { return tsubame_swift_abi_version(); }

TsubameStatus tsubame_engine_create(
    const uint8_t *path, size_t length,
    TsubameEngine **out_engine, TsubameError *out_error
) {
    void *handle = NULL;
    TsubameStatus status = tsubame_swift_engine_create(
        path, length, out_engine ? &handle : NULL, out_error);
    if (out_engine) *out_engine = (TsubameEngine *)handle;
    return status;
}
void tsubame_engine_destroy(TsubameEngine *engine) {
    tsubame_swift_engine_destroy(engine);
}
TsubameStatus tsubame_lookup(
    TsubameEngine *engine, const uint8_t *text, size_t length,
    size_t position, size_t limit,
    TsubameResult **out_result, TsubameError *out_error
) {
    void *handle = NULL;
    TsubameStatus status = tsubame_swift_lookup(
        engine, text, length, position, limit,
        out_result ? &handle : NULL, out_error);
    if (out_result) *out_result = (TsubameResult *)handle;
    return status;
}
TsubameStatus tsubame_scan(
    TsubameEngine *engine, const uint8_t *text, size_t length,
    size_t start, size_t end, size_t group_limit, size_t entries_limit,
    TsubameResult **out_result, TsubameError *out_error
) {
    void *handle = NULL;
    TsubameStatus status = tsubame_swift_scan(
        engine, text, length, start, end, group_limit, entries_limit,
        out_result ? &handle : NULL, out_error);
    if (out_result) *out_result = (TsubameResult *)handle;
    return status;
}
TsubameStatus tsubame_result_get_view(
    const TsubameResult *result, TsubameResultView *out_view
) {
    return tsubame_swift_result_get_view(result, out_view);
}
void tsubame_result_destroy(TsubameResult *result) {
    tsubame_swift_result_destroy(result);
}
TsubameStatus tsubame_content_get(
    const TsubameContent *content, const TsubameValue **out_value,
    TsubameError *out_error
) {
    return tsubame_swift_content_get(content, out_value, out_error);
}
void tsubame_error_free(TsubameError *error) {
    tsubame_swift_error_free(error);
}
