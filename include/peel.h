#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct PeelPolicy {
    const char *destination; /* nullable */
    uint32_t collision;      /* 0=error 1=overwrite 2=rename 3=skip */
    uint32_t enclosing;      /* 0=when_needed 1=always 2=never */
} PeelPolicy;

/* All returned char* are heap UTF-8 JSON; free with peel_string_free. */
char *peel_extract(const char *archive_path, PeelPolicy policy);
char *peel_list(const char *archive_path);
void peel_string_free(char *s);

#ifdef __cplusplus
}
#endif
