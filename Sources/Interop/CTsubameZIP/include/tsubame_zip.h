#ifndef TSUBAME_ZIP_H
#define TSUBAME_ZIP_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct tsubame_zip_archive tsubame_zip_archive;
typedef struct tsubame_zip_extract_iterator tsubame_zip_extract_iterator;

typedef enum tsubame_zip_entry_kind {
    TSUBAME_ZIP_ENTRY_FILE = 0,
    TSUBAME_ZIP_ENTRY_DIRECTORY = 1,
    TSUBAME_ZIP_ENTRY_SYMLINK = 2,
    TSUBAME_ZIP_ENTRY_OTHER = 3
} tsubame_zip_entry_kind;

typedef struct tsubame_zip_entry_info {
    uint64_t compressed_size;
    uint64_t uncompressed_size;
    tsubame_zip_entry_kind kind;
    int encrypted;
    int supported;
} tsubame_zip_entry_info;

int tsubame_zip_open(
    const char *utf8_path,
    tsubame_zip_archive **archive,
    char *error_buffer,
    size_t error_buffer_size
);
void tsubame_zip_close(tsubame_zip_archive *archive);
uint32_t tsubame_zip_entry_count(tsubame_zip_archive *archive);
uint32_t tsubame_zip_entry_name_size(tsubame_zip_archive *archive, uint32_t index);
int tsubame_zip_entry_name(
    tsubame_zip_archive *archive,
    uint32_t index,
    char *buffer,
    uint32_t buffer_size
);
int tsubame_zip_entry_get_info(
    tsubame_zip_archive *archive,
    uint32_t index,
    tsubame_zip_entry_info *info
);
tsubame_zip_extract_iterator *tsubame_zip_extract_begin(
    tsubame_zip_archive *archive,
    uint32_t index
);
size_t tsubame_zip_extract_read(
    tsubame_zip_extract_iterator *iterator,
    void *buffer,
    size_t buffer_size
);
int tsubame_zip_extract_finish(tsubame_zip_extract_iterator *iterator);
void tsubame_zip_last_error(
    tsubame_zip_archive *archive,
    char *error_buffer,
    size_t error_buffer_size
);

#ifdef __cplusplus
}
#endif

#endif
