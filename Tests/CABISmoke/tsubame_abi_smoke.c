#include "tsubame.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void fail(const char *message) {
    fprintf(stderr, "C ABI smoke failure: %s\n", message);
    exit(1);
}
static int equals(TsubameString value, const char *expected) {
    const size_t length = strlen(expected);
    return value.data != NULL && value.length == length &&
        memcmp(value.data, expected, length) == 0;
}
static void expect_ok(TsubameStatus status, const TsubameError *error) {
    if (status != TSUBAME_STATUS_OK) {
        if (error->message.data) fwrite(error->message.data, 1, error->message.length, stderr);
        fail("operation failed");
    }
    if (error->status != 0 || error->code.data || error->message.data) {
        fail("success returned an error");
    }
}
int main(int argc, char **argv) {
    static const char query[] = "食べました";
    static const char scan_text[] = "前食べましたｶﾞｸｾｲ後";
    TsubameEngine *engine = NULL;
    TsubameResult *result = NULL;
    TsubameResult *scan = NULL;
    TsubameError error = {0, {NULL, 0}, {NULL, 0}};
    TsubameResultView view = {NULL, 0};
    TsubameResultView scan_view = {NULL, 0};
    const TsubameValue *value = NULL;
    const TsubameValue *again = NULL;
    uint8_t *input;
    const TsubameEntry *entry;
    const TsubameDefinition *definition;
    TsubameStatus status;

    if (argc != 2) fail("expected a database path");
    if (tsubame_abi_version() != TSUBAME_ABI_VERSION) fail("unexpected ABI version");
    status = tsubame_engine_create(NULL, 1, &engine, &error);
    if (status != TSUBAME_STATUS_INVALID_ARGUMENT || engine != NULL ||
        error.status != status || !equals(error.code, "null_input")) {
        fail("invalid engine input was not rejected");
    }
    tsubame_error_free(&error);
    if (error.code.data || error.message.data || error.status) fail("error_free did not clear");
    tsubame_error_free(&error);

    expect_ok(tsubame_engine_create(
        (const uint8_t *)argv[1], strlen(argv[1]), &engine, &error), &error);
    input = (uint8_t *)malloc(sizeof(query) - 1);
    if (input == NULL) fail("allocation failed");
    memcpy(input, query, sizeof(query) - 1);
    status = tsubame_lookup(engine, input, sizeof(query) - 1, 0, 100, &result, &error);
    memset(input, 0, sizeof(query) - 1);
    free(input);
    expect_ok(status, &error);
    if (!result || tsubame_result_get_view(result, &view) != TSUBAME_STATUS_OK ||
        view.group_count != 1 || !view.groups || view.groups[0].entry_count != 1 ||
        view.groups[0].source_range.start != 0 || view.groups[0].source_range.end != 15) {
        fail("unexpected lookup groups");
    }
    entry = &view.groups[0].entries[0];
    if (!equals(entry->expression, "食べる") || !equals(entry->reading, "たべる") ||
        entry->match_count != 1 || entry->matches[0].key_type != TSUBAME_KEY_EXPRESSION ||
        entry->definition_count == 0) {
        fail("unexpected entry");
    }
    definition = &entry->definitions[0];

    expect_ok(tsubame_scan(engine, (const uint8_t *)scan_text, sizeof(scan_text) - 1,
        3, 33, 100, 100, &scan, &error), &error);
    if (tsubame_result_get_view(scan, &scan_view) != TSUBAME_STATUS_OK ||
        scan_view.group_count != 3 ||
        scan_view.groups[0].source_range.start != 3 ||
        scan_view.groups[0].source_range.end != 18 ||
        scan_view.groups[1].source_range.start != 3 ||
        scan_view.groups[1].source_range.end != 9 ||
        scan_view.groups[2].source_range.start != 18 ||
        scan_view.groups[2].source_range.end != 33 ||
        !equals(scan_view.groups[2].entries[0].expression, "ガクセイ")) {
        fail("unexpected scan groups");
    }
    tsubame_result_destroy(scan);
    scan = NULL;

    status = tsubame_lookup(engine, NULL, 1, 0, 100, &scan, &error);
    if (status != TSUBAME_STATUS_INVALID_ARGUMENT || scan != NULL) {
        fail("invalid lookup input was not rejected");
    }
    tsubame_error_free(&error);
    tsubame_engine_destroy(engine);
    engine = NULL;

    /* Result memory is independent of the engine, input and later queries. */
    if (!equals(entry->expression, "食べる")) fail("result did not survive engine destruction");
    expect_ok(tsubame_content_get(definition->content, &value, &error), &error);
    if (!value || value->kind != TSUBAME_VALUE_STRING ||
        !equals(value->value.string_value, "to eat")) fail("unexpected typed content");
    expect_ok(tsubame_content_get(definition->content, &again, &error), &error);
    if (again != value) fail("content was not cached");
    tsubame_result_destroy(result);
    tsubame_result_destroy(NULL);
    tsubame_engine_destroy(NULL);
    tsubame_error_free(NULL);
    puts("Tsubame C ABI smoke passed.");
    return 0;
}
