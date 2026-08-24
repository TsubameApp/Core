#include "tsubame.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void fail(const char *message) {
    fprintf(stderr, "C ABI smoke failure: %s\n", message);
    exit(1);
}

static int contains_bytes(
    const TsubameBuffer *buffer,
    const char *needle
) {
    const size_t needle_length = strlen(needle);
    size_t offset;

    if (needle_length == 0) {
        return 1;
    }
    if (buffer->data == NULL || needle_length > buffer->length) {
        return 0;
    }
    for (offset = 0; offset <= buffer->length - needle_length; offset += 1) {
        if (memcmp(buffer->data + offset, needle, needle_length) == 0) {
            return 1;
        }
    }
    return 0;
}

static void print_error(const TsubameBuffer *error) {
    if (error->data != NULL && error->length > 0) {
        fwrite(error->data, 1, error->length, stderr);
        fputc('\n', stderr);
    }
}

static TsubameBuffer execute_success(
    TsubameEngine *engine,
    const uint8_t *request,
    size_t request_length
) {
    TsubameBuffer result = {NULL, 0};
    TsubameBuffer error = {NULL, 0};
    const TsubameStatus status = tsubame_engine_execute(
        engine,
        TSUBAME_SERIALIZATION_JSON_V1,
        request,
        request_length,
        &result,
        &error
    );

    if (status != TSUBAME_STATUS_OK) {
        print_error(&error);
        tsubame_buffer_free(&error);
        fail("execute returned a failure status");
    }
    if (result.data == NULL || result.length == 0) {
        tsubame_buffer_free(&result);
        fail("execute returned an empty result");
    }
    if (error.data != NULL || error.length != 0) {
        tsubame_buffer_free(&result);
        tsubame_buffer_free(&error);
        fail("successful execute returned an error buffer");
    }
    return result;
}

static void expect_failure(
    TsubameEngine *engine,
    const uint8_t *request,
    size_t request_length,
    TsubameStatus expected_status,
    const char *expected_error_code
) {
    TsubameBuffer result = {NULL, 0};
    TsubameBuffer error = {NULL, 0};
    const TsubameStatus status = tsubame_engine_execute(
        engine,
        TSUBAME_SERIALIZATION_JSON_V1,
        request,
        request_length,
        &result,
        &error
    );

    if (status != expected_status) {
        print_error(&error);
        fail("execute returned an unexpected failure status");
    }
    if (result.data != NULL || result.length != 0) {
        fail("failed execute returned a result buffer");
    }
    if (!contains_bytes(&error, expected_error_code)) {
        print_error(&error);
        fail("failed execute returned an unexpected error payload");
    }
    tsubame_buffer_free(&error);
    if (error.data != NULL || error.length != 0) {
        fail("buffer_free did not clear the error buffer");
    }
    tsubame_buffer_free(&error);
}

int main(int argc, char **argv) {
    static const char positioned_request[] =
        "{\"schemaVersion\":1,\"operation\":\"positionedLookup\","
        "\"request\":{\"text\":\"食べました\",\"position\":0,"
        "\"resultLimit\":100}}";
    static const char scan_request[] =
        "{\"schemaVersion\":1,\"operation\":\"rangeScan\","
        "\"request\":{\"text\":\"前食べましたｶﾞｸｾｲ後\","
        "\"range\":{\"start\":3,\"end\":33},"
        "\"resultGroupLimit\":100,\"entriesPerGroupLimit\":100}}";
    static const uint8_t malformed_utf8[] = {0xC3, 0x28};
    static const char malformed_json[] = "{";
    TsubameEngine *engine = NULL;
    TsubameBuffer error = {NULL, 0};
    TsubameBuffer positioned;
    TsubameBuffer positioned_again;
    TsubameBuffer scan;
    TsubameStatus status;
    char *database_path;
    size_t database_path_length;

    if (argc != 2) {
        fail("expected one dictionary.sqlite path argument");
    }
    if (tsubame_abi_version() != TSUBAME_ABI_VERSION) {
        fail("unexpected ABI version");
    }

    status = tsubame_engine_create(NULL, 1, &engine, &error);
    if (status != TSUBAME_STATUS_INVALID_ARGUMENT || engine != NULL) {
        fail("NULL plus nonzero length was not rejected");
    }
    if (!contains_bytes(&error, "null_input")) {
        print_error(&error);
        fail("invalid pointer pair returned an unexpected error");
    }
    tsubame_buffer_free(&error);

    database_path_length = strlen(argv[1]);
    database_path = (char *)malloc(database_path_length);
    if (database_path == NULL) {
        fail("could not allocate the path input buffer");
    }
    memcpy(database_path, argv[1], database_path_length);
    status = tsubame_engine_create(
        (const uint8_t *)database_path,
        database_path_length,
        &engine,
        &error
    );
    memset(database_path, 0, database_path_length);
    free(database_path);
    if (status != TSUBAME_STATUS_OK || engine == NULL) {
        print_error(&error);
        tsubame_buffer_free(&error);
        fail("engine creation failed");
    }
    if (error.data != NULL || error.length != 0) {
        fail("engine creation returned an error buffer on success");
    }

    positioned = execute_success(
        engine,
        (const uint8_t *)positioned_request,
        sizeof(positioned_request) - 1
    );
    if (!contains_bytes(&positioned, "\"expression\":\"食べる\"")) {
        fail("positioned lookup did not deinflect 食べました to 食べる");
    }
    if (!contains_bytes(&positioned, "\"sourceRange\":{\"end\":15,\"start\":0}")) {
        fail("positioned lookup returned an unexpected source range");
    }

    positioned_again = execute_success(
        engine,
        (const uint8_t *)positioned_request,
        sizeof(positioned_request) - 1
    );
    if (positioned.length != positioned_again.length ||
        memcmp(positioned.data, positioned_again.data, positioned.length) != 0) {
        fail("JSON serialization is not deterministic");
    }
    tsubame_buffer_free(&positioned_again);
    tsubame_buffer_free(&positioned);
    if (positioned.data != NULL || positioned.length != 0) {
        fail("buffer_free did not clear the positioned result");
    }
    tsubame_buffer_free(&positioned);

    scan = execute_success(
        engine,
        (const uint8_t *)scan_request,
        sizeof(scan_request) - 1
    );
    if (!contains_bytes(&scan, "\"sourceRange\":{\"end\":18,\"start\":3}") ||
        !contains_bytes(&scan, "\"sourceRange\":{\"end\":9,\"start\":3}") ||
        !contains_bytes(&scan, "\"sourceRange\":{\"end\":33,\"start\":18}")) {
        fail("range scan did not preserve absolute original UTF-8 ranges");
    }
    if (!contains_bytes(&scan, "\"expression\":\"食べる\"") ||
        !contains_bytes(&scan, "\"expression\":\"ガクセイ\"")) {
        fail("range scan did not return the expected dictionary entries");
    }
    tsubame_buffer_free(&scan);

    expect_failure(
        engine,
        malformed_utf8,
        sizeof(malformed_utf8),
        TSUBAME_STATUS_INVALID_UTF8,
        "invalid_request_utf8"
    );
    expect_failure(
        engine,
        (const uint8_t *)malformed_json,
        sizeof(malformed_json) - 1,
        TSUBAME_STATUS_INVALID_JSON,
        "malformed_json"
    );

    tsubame_engine_destroy(engine);
    tsubame_engine_destroy(NULL);
    puts("Tsubame C ABI smoke passed.");
    return 0;
}
