CC := clang

CFLAGS := -Wall -Wextra -Werror -std=c11 -Iinclude -Isrc $(shell pkg-config --cflags libcrypto)
LDFLAGS := -lchoma -lappsign -framework CoreFoundation -framework Foundation -framework Security

DEBUG ?= 0
ifeq ($(DEBUG), 1)
	CFLAGS += -g -O0
else
	CFLAGS += -O3
endif

BUILD_DIR=build

LIB_SRCS := $(filter-out src/main.c, $(wildcard src/*.c))
LIB_OBJS := $(LIB_SRCS:src/%.c=$(BUILD_DIR)/%.o)

TOOL_SRCS := src/main.c
TOOL_OBJS := build/main.o

TARGET ?= ios

CHOMA_MAKE_ARGS := DISABLE_TESTS=1 DEBUG=0

ifeq ($(TARGET), ios)
	OUTPUT_DIR=output/ios
	CFLAGS += -arch arm64 -arch arm64e -isysroot $(shell xcrun --sdk iphoneos --show-sdk-path) -miphoneos-version-min=13.4
	LDFLAGS += -arch arm64 -arch arm64e -isysroot $(shell xcrun --sdk iphoneos --show-sdk-path) -miphoneos-version-min=13.4
	CFLAGS += -Ithird-party/ChOma/output/ios/include
	LDFLAGS += -Lthird-party/ChOma/output/ios/lib -L$(OUTPUT_DIR)/lib
	TOOL_OBJS += external/ios/libcrypto.a
	CHOMA_MAKE_ARGS += TARGET=ios
else ifeq ($(TARGET), host)
	OUTPUT_DIR=output
	CFLAGS += -Ithird-party/ChOma/output/include
	LDFLAGS += -Lthird-party/ChOma/output/lib -L$(OUTPUT_DIR)/lib $(shell pkg-config --libs libcrypto)
endif

.PHONY: copy-headers lib deps clean clean-all

lib: $(OUTPUT_DIR)/lib/libappsign.a

tool: $(OUTPUT_DIR)/bin/appsign

ifeq ($(TARGET), ios)
$(OUTPUT_DIR)/bin/appsign: $(TOOL_OBJS) | $(OUTPUT_DIR)/lib/libappsign.a $(OUTPUT_DIR)/bin
	$(CC) $^ -o $@ $(LDFLAGS)
	ldid -S $@
else
$(OUTPUT_DIR)/bin/appsign: $(TOOL_OBJS) | $(OUTPUT_DIR)/lib/libappsign.a $(OUTPUT_DIR)/bin
	$(CC) $^ -o $@ $(LDFLAGS)
endif

$(OUTPUT_DIR)/lib/libappsign.a: $(LIB_OBJS) | copy-headers
	libtool -static -o $@ $^

build/%.o: src/%.c $(BUILD_DIR) deps
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)
	@mkdir -p $(OUTPUT_DIR)/include/appsign $(OUTPUT_DIR)/lib

$(OUTPUT_DIR)/bin:
	@mkdir -p $(OUTPUT_DIR)/bin

copy-headers: $(wildcard include/*.h)
	@cp $^ $(OUTPUT_DIR)/include/appsign

deps:
	$(MAKE) -C third-party/ChOma $(OUTPUT_DIR)/lib/libchoma.a copy-choma-headers $(CHOMA_MAKE_ARGS)

clean:
	@rm -rf build output

clean-all: clean
	$(MAKE) -C third-party/ChOma clean-all
