#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <copyfile.h>
#include <sys/stat.h>
#include <dirent.h>
#include <mach-o/fat.h>
#include <mach-o/loader.h>
#include <choma/MemoryStream.h>
#include <choma/FileStream.h>
#include "ct_bypass.h"
#include "file.h"
#include "codesign.h"

int process_binary(const char *path, NSDictionary *entitelements) {
    int res = codesign_sign_adhoc(path, true, entitelements);
    if (res != 0) {
		fprintf(stderr, "Failed adhoc signing (%d) Continuing anyways...\n", res);
	}
    else {
        printf("AdHoc signed file!\n");
    }

    char *macho_path = extract_best_slice(path);
    if (!macho_path) {
        fprintf(stderr, "Failed to extract best slice for '%s'.\n", path);
        return -1;
    }

    res = apply_ct_bypass(macho_path);
    if (res != 0) {
        fprintf(stderr, "Failed to apply CoreTrust bypass exploit.\n");
        return res;
    }

    if(copyfile(macho_path, path, 0, COPYFILE_ALL | COPYFILE_MOVE | COPYFILE_UNLINK) == 0) {
        chmod(path, 0755);
    } else {
        perror("copyfile");
        return -1;
    }

    free(macho_path);
    return 0;
}

int process_bundle(const char *bundle_path, NSDictionary *entitelements) {
    DIR *dir;
    struct dirent *entry;
    struct stat statbuf;
    int r = 0;

    if ((dir = opendir(bundle_path)) == NULL) {
        perror("opendir");
        return -1;
    }

    while ((entry = readdir(dir)) != NULL) {
        char fullpath[1024];
        snprintf(fullpath, sizeof(fullpath), "%s/%s", bundle_path, entry->d_name);

        if (stat(fullpath, &statbuf) == -1) {
            perror("stat");
            return -1;
        }

        if (S_ISDIR(statbuf.st_mode)) {
            if (strcmp(entry->d_name, ".") != 0 && strcmp(entry->d_name, "..") != 0) {
                // Recursive call for subdirectories
                r = process_bundle(fullpath, entitelements);
            }
        } else {
            // Process file
            MemoryStream *stream = file_stream_init_from_path(fullpath, 0, 0, 0);
            if (!stream) {
                fprintf(stderr, "Failed to open file %s\n", fullpath);
                continue;
            }
            uint32_t magic = 0;
            memory_stream_read(stream, 0, sizeof(magic), &magic);
            if (magic == FAT_MAGIC_64 || magic == MH_MAGIC_64) {
                printf("Applying bypass to %s.\n", fullpath);
                r = process_binary(fullpath, entitelements);
                if (r != 0) {
                    fprintf(stderr, "Failed to apply bypass to %s\n", fullpath);
                    closedir(dir);
                    return r;
                }
            }
            memory_stream_free(stream);
        }
    }

    closedir(dir);
    return r;
}

void print_usage(const char *bin) {
    fprintf(stderr, "Usage: %s path [-e | --entitelements entitlements.plist]\n", bin);
}

int main(int argc, char **argv) {
    if (argc != 2 && argc != 4) {
        print_usage(argv[0]);
        return -1;
    }

    NSDictionary *custom_entitlements = nil;
    if (argc == 4) {
        if (!strcmp(argv[2], "--entitlements") || !strcmp(argv[2], "-e")) {
            NSString *entitlements_path = [NSString stringWithUTF8String:argv[3]];
            printf("Using custom entitlements from %s\n", [entitlements_path UTF8String]);
            custom_entitlements = [NSDictionary dictionaryWithContentsOfFile:entitlements_path];
        }
    }

    const char *path = argv[1];
    const char *ext = get_extension(path);
    int is_bundle = strcmp(ext, "app") == 0;

    int res = -1;
    if (is_bundle) {
        res = process_bundle(path, custom_entitlements);
    } else {
        res = process_binary(path, custom_entitlements);
    }

    if (res != 0) {
        fprintf(stderr, "Failed to apply CoreTrust bypass to '%s'\n", path);
    } else {
        printf("Successfully applied CoreTrust bypass to '%s'\n", path);
    }
    
    return res;
}
