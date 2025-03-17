#include "file.h"

#include <string.h>

const char *get_extension(const char *path) {
    const char *dot = strrchr(path, '.');
    if (!dot || dot == path) {
        return "";
    }
    return dot + 1;
}