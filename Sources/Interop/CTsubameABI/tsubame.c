#include "tsubame.h"

/* Private bridge implemented by @c functions in TsubameCore. Keep these
 * declarations out of the public header: clients only use the stable wrapper
 * functions below. SwiftPM does not expose generated Swift compatibility
 * headers to dependent C targets consistently on every supported platform. */
extern uint32_t tsubame_swift_abi_version(void);
extern TsubameStatus tsubame_swift_engine_create(
    const uint8_t *database_path,
    size_t database_path_length,
    void **out_engine,
    uint8_t **out_error_data,
    size_t *out_error_length
);
extern void tsubame_swift_engine_destroy(void *engine);
extern TsubameStatus tsubame_swift_engine_execute(
    void *engine,
    uint32_t serialization,
    const uint8_t *request,
    size_t request_length,
    uint8_t **out_result_data,
    size_t *out_result_length,
    uint8_t **out_error_data,
    size_t *out_error_length
);
extern void tsubame_swift_buffer_free(uint8_t *data);

uint32_t
tsubame_abi_version(void) {
    return tsubame_swift_abi_version();
}

TsubameStatus
tsubame_engine_create(
    const uint8_t *database_path,
    size_t database_path_length,
    TsubameEngine **out_engine,
    TsubameBuffer *out_error
) {
    if (out_engine != NULL) {
        *out_engine = NULL;
    }
    if (out_error != NULL) {
        out_error->data = NULL;
        out_error->length = 0;
    }
    if (out_engine == NULL || out_error == NULL) {
        return TSUBAME_STATUS_INVALID_ARGUMENT;
    }

    return tsubame_swift_engine_create(
        database_path,
        database_path_length,
        (void **)out_engine,
        &out_error->data,
        &out_error->length
    );
}

void
tsubame_engine_destroy(TsubameEngine *engine) {
    tsubame_swift_engine_destroy((void *)engine);
}

TsubameStatus
tsubame_engine_execute(
    TsubameEngine *engine,
    uint32_t serialization,
    const uint8_t *request,
    size_t request_length,
    TsubameBuffer *out_result,
    TsubameBuffer *out_error
) {
    if (out_result != NULL) {
        out_result->data = NULL;
        out_result->length = 0;
    }
    if (out_error != NULL && out_error != out_result) {
        out_error->data = NULL;
        out_error->length = 0;
    }
    if (engine == NULL || out_result == NULL || out_error == NULL || out_result == out_error) {
        return TSUBAME_STATUS_INVALID_ARGUMENT;
    }

    return tsubame_swift_engine_execute(
        (void *)engine,
        serialization,
        request,
        request_length,
        &out_result->data,
        &out_result->length,
        &out_error->data,
        &out_error->length
    );
}

void
tsubame_buffer_free(TsubameBuffer *buffer) {
    if (buffer == NULL) {
        return;
    }

    tsubame_swift_buffer_free(buffer->data);
    buffer->data = NULL;
    buffer->length = 0;
}
