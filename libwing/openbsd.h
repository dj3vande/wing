#ifndef H_WING_OPENBSD
#define H_WING_OPENBSD

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

void *reallocarray(void *optr, size_t nmemb, size_t size);
size_t strlcpy(char *dst, const char *src, size_t siz);

#ifdef __cplusplus
}
#endif

#endif	/*H_WING_OPENBSD #include guard*/
