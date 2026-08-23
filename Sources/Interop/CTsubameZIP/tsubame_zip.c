#include "tsubame_zip.h"

#include "miniz.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#endif

struct tsubame_zip_archive {
    mz_zip_archive zip;
    FILE *file;
};

struct tsubame_zip_extract_iterator {
    mz_zip_reader_extract_iter_state *state;
};

static void tsubame_copy_error(const char *message, char *buffer, size_t buffer_size) {
    if (!buffer || !buffer_size) {
        return;
    }

    if (!message) {
        message = "Unknown ZIP error";
    }

    size_t length = strlen(message);
    if (length >= buffer_size) {
        length = buffer_size - 1;
    }
    memcpy(buffer, message, length);
    buffer[length] = '\0';
}

static FILE *tsubame_open_utf8_file(const char *path) {
#ifdef _WIN32
    if (!path) {
        return NULL;
    }

    int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, NULL, 0);
    if (!length) {
        return NULL;
    }

    wchar_t *wide_path = (wchar_t *)malloc((size_t)length * sizeof(wchar_t));
    if (!wide_path) {
        return NULL;
    }

    if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, wide_path, length)) {
        free(wide_path);
        return NULL;
    }

    FILE *file = _wfopen(wide_path, L"rb");
    free(wide_path);
    return file;
#else
    return fopen(path, "rb");
#endif
}

int tsubame_zip_open(
    const char *utf8_path,
    tsubame_zip_archive **output,
    char *error_buffer,
    size_t error_buffer_size
) {
    if (!utf8_path || !output) {
        tsubame_copy_error("Invalid ZIP path", error_buffer, error_buffer_size);
        return 0;
    }

    *output = NULL;
    tsubame_zip_archive *archive = (tsubame_zip_archive *)calloc(1, sizeof(*archive));
    if (!archive) {
        tsubame_copy_error("Could not allocate ZIP reader", error_buffer, error_buffer_size);
        return 0;
    }

    archive->file = tsubame_open_utf8_file(utf8_path);
    if (!archive->file) {
        tsubame_copy_error("Could not open ZIP file", error_buffer, error_buffer_size);
        free(archive);
        return 0;
    }

    mz_zip_zero_struct(&archive->zip);
    if (!mz_zip_reader_init_cfile(&archive->zip, archive->file, 0, 0)) {
        tsubame_copy_error(
            mz_zip_get_error_string(mz_zip_peek_last_error(&archive->zip)),
            error_buffer,
            error_buffer_size
        );
        fclose(archive->file);
        free(archive);
        return 0;
    }

    *output = archive;
    return 1;
}

void tsubame_zip_close(tsubame_zip_archive *archive) {
    if (!archive) {
        return;
    }
    mz_zip_reader_end(&archive->zip);
    if (archive->file) {
        fclose(archive->file);
    }
    free(archive);
}

uint32_t tsubame_zip_entry_count(tsubame_zip_archive *archive) {
    return archive ? (uint32_t)mz_zip_reader_get_num_files(&archive->zip) : 0;
}

uint32_t tsubame_zip_entry_name_size(tsubame_zip_archive *archive, uint32_t index) {
    return archive ? (uint32_t)mz_zip_reader_get_filename(&archive->zip, index, NULL, 0) : 0;
}

int tsubame_zip_entry_name(
    tsubame_zip_archive *archive,
    uint32_t index,
    char *buffer,
    uint32_t buffer_size
) {
    if (!archive || !buffer || !buffer_size) {
        return 0;
    }
    return mz_zip_reader_get_filename(&archive->zip, index, buffer, buffer_size) != 0;
}

int tsubame_zip_entry_get_info(
    tsubame_zip_archive *archive,
    uint32_t index,
    tsubame_zip_entry_info *info
) {
    if (!archive || !info) {
        return 0;
    }

    mz_zip_archive_file_stat stat;
    if (!mz_zip_reader_file_stat(&archive->zip, index, &stat)) {
        return 0;
    }

    info->compressed_size = stat.m_comp_size;
    info->uncompressed_size = stat.m_uncomp_size;
    info->encrypted = stat.m_is_encrypted != 0;
    info->supported = stat.m_is_supported != 0;

    uint32_t unix_mode = stat.m_external_attr >> 16;
    uint32_t file_type = unix_mode & 0170000U;
    if (file_type == 0120000U) {
        info->kind = TSUBAME_ZIP_ENTRY_SYMLINK;
    } else if (stat.m_is_directory || file_type == 0040000U) {
        info->kind = TSUBAME_ZIP_ENTRY_DIRECTORY;
    } else if (file_type != 0 && file_type != 0100000U) {
        info->kind = TSUBAME_ZIP_ENTRY_OTHER;
    } else {
        info->kind = TSUBAME_ZIP_ENTRY_FILE;
    }

    return 1;
}

tsubame_zip_extract_iterator *tsubame_zip_extract_begin(
    tsubame_zip_archive *archive,
    uint32_t index
) {
    if (!archive) {
        return NULL;
    }

    mz_zip_reader_extract_iter_state *state =
        mz_zip_reader_extract_iter_new(&archive->zip, index, 0);
    if (!state) {
        return NULL;
    }

    tsubame_zip_extract_iterator *iterator =
        (tsubame_zip_extract_iterator *)malloc(sizeof(*iterator));
    if (!iterator) {
        mz_zip_reader_extract_iter_free(state);
        return NULL;
    }
    iterator->state = state;
    return iterator;
}

size_t tsubame_zip_extract_read(
    tsubame_zip_extract_iterator *iterator,
    void *buffer,
    size_t buffer_size
) {
    if (!iterator || !iterator->state || !buffer) {
        return 0;
    }
    return mz_zip_reader_extract_iter_read(iterator->state, buffer, buffer_size);
}

int tsubame_zip_extract_finish(tsubame_zip_extract_iterator *iterator) {
    if (!iterator) {
        return 0;
    }
    int result = mz_zip_reader_extract_iter_free(iterator->state) != 0;
    free(iterator);
    return result;
}

void tsubame_zip_last_error(
    tsubame_zip_archive *archive,
    char *error_buffer,
    size_t error_buffer_size
) {
    const char *message = archive
        ? mz_zip_get_error_string(mz_zip_peek_last_error(&archive->zip))
        : "Unknown ZIP error";
    tsubame_copy_error(message, error_buffer, error_buffer_size);
}
