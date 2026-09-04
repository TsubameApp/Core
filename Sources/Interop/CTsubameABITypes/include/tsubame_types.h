#ifndef TSUBAME_TYPES_H
#define TSUBAME_TYPES_H
#include <stddef.h>
#include <stdint.h>

typedef struct TsubameEngine TsubameEngine;
typedef struct TsubameResult TsubameResult;
typedef struct TsubameContent TsubameContent;

typedef int32_t TsubameStatus;
enum {
    TSUBAME_STATUS_OK = 0,
    TSUBAME_STATUS_INVALID_ARGUMENT = 1,
    TSUBAME_STATUS_INVALID_UTF8 = 2,
    TSUBAME_STATUS_INVALID_REQUEST = 3,
    TSUBAME_STATUS_ENGINE_OPEN_FAILED = 4,
    TSUBAME_STATUS_EXECUTION_FAILED = 5,
    TSUBAME_STATUS_INTERNAL_ERROR = 255
};

/* UTF-8, not NUL-terminated. For optional fields NULL means absent; an empty
 * but present string has a non-NULL pointer and length zero. */
typedef struct TsubameString {
    const uint8_t *data;
    size_t length;
} TsubameString;

/* Owned diagnostic strings. Initialize to {0}; release with error_free before
 * reusing this output slot. Do not copy an owning error and free both copies. */
typedef struct TsubameError {
    TsubameStatus status;
    TsubameString code;
    TsubameString message;
} TsubameError;

typedef struct TsubameRange { size_t start; size_t end; } TsubameRange;
typedef uint32_t TsubameLookupKeyType;
enum { TSUBAME_KEY_EXPRESSION = 0, TSUBAME_KEY_READING = 1 };

typedef struct TsubameMatch {
    TsubameString key;
    TsubameLookupKeyType key_type;
} TsubameMatch;
typedef struct TsubameDefinition {
    size_t position;
    TsubameString kind;
    TsubameString text;
    const TsubameContent *content;
} TsubameDefinition;
typedef struct TsubameEntry {
    int64_t id;
    TsubameString expression;
    TsubameString reading;
    TsubameString definition_tags;
    TsubameString rules;
    double score;
    int64_t sequence;
    TsubameString term_tags;
    const TsubameMatch *matches;
    size_t match_count;
    const TsubameDefinition *definitions;
    size_t definition_count;
} TsubameEntry;
typedef struct TsubameGroup {
    TsubameRange source_range;
    const TsubameEntry *entries;
    size_t entry_count;
} TsubameGroup;
typedef struct TsubameResultView {
    const TsubameGroup *groups;
    size_t group_count;
} TsubameResultView;

typedef uint32_t TsubameValueKind;
enum {
    TSUBAME_VALUE_NULL = 0,
    TSUBAME_VALUE_BOOLEAN = 1,
    TSUBAME_VALUE_INTEGER = 2,
    TSUBAME_VALUE_NUMBER = 3,
    TSUBAME_VALUE_STRING = 4,
    TSUBAME_VALUE_ARRAY = 5,
    TSUBAME_VALUE_OBJECT = 6
};
typedef struct TsubameValue TsubameValue;
typedef struct TsubameMember TsubameMember;
typedef struct TsubameValueArray {
    const TsubameValue *data;
    size_t count;
} TsubameValueArray;
typedef struct TsubameMemberArray {
    const TsubameMember *data;
    size_t count;
} TsubameMemberArray;
typedef union TsubameValueData {
    uint8_t boolean_value;
    int64_t integer_value;
    double number_value;
    TsubameString string_value;
    TsubameValueArray array_value;
    TsubameMemberArray object_value;
} TsubameValueData;
struct TsubameValue {
    TsubameValueKind kind;
    TsubameValueData value;
};
struct TsubameMember {
    TsubameString key;
    TsubameValue value;
};
#endif
