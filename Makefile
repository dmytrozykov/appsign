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

LIB_C_SRCS := $(filter-out src/main.c, $(wildcard src/*.c))
LIB_OBJC_SRC := $(filter-out src/main.m, $(wildcard src/*.m))
LIB_OBJS := $(LIB_C_SRCS:src/%.c=$(BUILD_DIR)/%.c.o) $(LIB_OBJC_SRC:src/%.m=$(BUILD_DIR)/%.m.o)

TOOL_SRCS := src/main.m
TOOL_OBJS := build/main.m.o

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

$(OUTPUT_DIR)/lib/libappsign.a: $(LIB_OBJS) | copy-headers $(OUTPUT_DIR)/lib
	libtool -static -o $@ $^

build/%.c.o: src/%.c $(BUILD_DIR) deps
	$(CC) $(CFLAGS) -c $< -o $@

build/%.m.o: src/%.m $(BUILD_DIR) deps
	$(CC) $(CFLAGS) -fobjc-arc -c $< -o $@

copy-headers: $(wildcard include/*.h) | $(OUTPUT_DIR)/include/appsign
	@cp $^ $(OUTPUT_DIR)/include/appsign

$(BUILD_DIR):
	@mkdir -p $@

$(OUTPUT_DIR)/include/appsign:
	@mkdir -p $@

$(OUTPUT_DIR)/lib:
	@mkdir -p $@

$(OUTPUT_DIR)/bin:
	@mkdir -p $@

deps:
	$(MAKE) -C third-party/ChOma $(OUTPUT_DIR)/lib/libchoma.a copy-choma-headers $(CHOMA_MAKE_ARGS)

clean:
	@rm -rf build output

clean-all: clean
	$(MAKE) -C third-party/ChOma clean-all
