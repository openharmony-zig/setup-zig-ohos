#!/usr/bin/env bash

set -eux

: "${INPUT_TAG:?INPUT_TAG needs to be set}"
: "${INPUT_CACHE:?INPUT_CACHE needs to be set}"

# Base URL for Zig OHOS releases
URL_BASE="https://github.com/openharmony-zig/zig-patch/releases/download"

# Determine platform and set OS_FILENAME
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # musl or gnu
    if command -v ldd >/dev/null 2>&1; then
        LDD_OUTPUT=$(ldd --version 2>&1 || true)
        if echo "$LDD_OUTPUT" | grep -i "musl" >/dev/null; then
            OS_FILENAME="zig-x86_64-linux-musl-baseline.tar.gz"
            OS="linux-musl"
        else
            OS_FILENAME="zig-x86_64-linux-gnu-baseline.tar.gz"
            OS="linux-gnu"
        fi
    else
        # default use gnu
        OS_FILENAME="zig-x86_64-linux-gnu-baseline.tar.gz"
        OS="linux-gnu"
    fi
elif [[ "$OSTYPE" == "darwin"* ]]; then
    if [[ $(uname -m) == 'arm64' ]]; then
        OS_FILENAME="zig-aarch64-macos-none-baseline.tar.gz"
        OS="macos-arm64"
    else
        echo "Error: Only ARM64 macOS is supported"
        exit 1
    fi
elif [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]]; then
    OS_FILENAME="zig-x86_64-windows-gnu-baseline.tar.gz"
    OS="windows"
else
    echo "Error: Unsupported OS type. Supported platforms:"
    echo "  - aarch64 macOS (Apple Silicon)"
    echo "  - x86_64 Windows"
    echo "  - x86_64 Linux (musl)"
    echo "  - x86_64 Linux (gnu)"
    exit 1
fi

WORK_DIR="${HOME}/setup-zig-ohos"
mkdir -p "${WORK_DIR}"
cd "${WORK_DIR}"

echo "Working directory: $WORK_DIR"
echo "Platform: $OS"
echo "Tag: $INPUT_TAG"

# check if cached
if [[ "$INPUT_WAS_CACHED" == "true" ]]; then
    echo "Using cached Zig OHOS installation"
    ZIG_DIR="${WORK_DIR}/zig"
    
    # verify cached installation
    if [[ -f "${ZIG_DIR}/zig" ]] || [[ -f "${ZIG_DIR}/zig.exe" ]]; then
        echo "Cached installation verified"
        
        # add to PATH
        echo "${ZIG_DIR}" >> $GITHUB_PATH
        echo "Added ${ZIG_DIR} to PATH"
        
        # get version and set output
        if [[ -f "${ZIG_DIR}/zig" ]]; then
            ZIG_VERSION=$(${ZIG_DIR}/zig version)
        else
            ZIG_VERSION=$(${ZIG_DIR}/zig.exe version)
        fi
        
        echo "zig-path=$ZIG_DIR" >> "${GITHUB_OUTPUT}"
        echo "zig-version=$ZIG_VERSION" >> "${GITHUB_OUTPUT}"
        echo "platform=$OS" >> "${GITHUB_OUTPUT}"
        exit 0
    else
        echo "Cached installation is invalid, will re-download"
        rm -rf "${ZIG_DIR}" 2>/dev/null || true
    fi
fi

# URL encode the tag for proper download URL
ENCODED_TAG=$(echo "$INPUT_TAG" | sed 's/+/%2B/g')

# Construct download URL
DOWNLOAD_URL="${URL_BASE}/${ENCODED_TAG}/${OS_FILENAME}"

echo "Downloading Zig OHOS from ${DOWNLOAD_URL}"

# Download with retry mechanism
RETRY_COUNT=0
MAX_RETRIES=3

while [[ $RETRY_COUNT -lt $MAX_RETRIES ]]; do
    if curl -L --fail --show-error --silent --max-time 300 -o "zig-ohos.tar.gz" "$DOWNLOAD_URL"; then
        echo "Download completed successfully"
        break
    else
        RETRY_COUNT=$((RETRY_COUNT + 1))
        echo "Download failed (attempt $RETRY_COUNT/$MAX_RETRIES)"
        if [[ $RETRY_COUNT -lt $MAX_RETRIES ]]; then
            echo "Retrying in 5 seconds..."
            sleep 5
        else
            echo "Error: Failed to download after $MAX_RETRIES attempts"
            echo "Please check if the release exists: $DOWNLOAD_URL"
            exit 1
        fi
    fi
done

# Verify download
if [[ ! -f "zig-ohos.tar.gz" ]] || [[ ! -s "zig-ohos.tar.gz" ]]; then
    echo "Error: Downloaded file is missing or empty"
    exit 1
fi

# Extract the archive
echo "Extracting Zig OHOS..."
tar -xzf "zig-ohos.tar.gz"

# Find the extracted directory (should start with 'zig-')
ZIG_EXTRACTED_DIR=$(find . -maxdepth 1 -name "zig-*" -type d | head -n 1)

if [[ -z "$ZIG_EXTRACTED_DIR" ]]; then
    echo "Error: Could not find extracted Zig directory"
    echo "Archive contents:"
    tar -tzf "zig-ohos.tar.gz" | head -10
    exit 1
fi

echo "Found extracted directory: $ZIG_EXTRACTED_DIR"

# Rename to standard 'zig' directory
mv "$ZIG_EXTRACTED_DIR" "zig"
ZIG_DIR="${WORK_DIR}/zig"

# Clean up the archive
rm "zig-ohos.tar.gz"

# Make sure the executable is executable (for Unix-like systems)
if [[ "$OS" != "windows" ]]; then
    chmod +x "$ZIG_EXECUTABLE"
fi

# Add Zig to PATH for subsequent steps
echo "${ZIG_DIR}" >> $GITHUB_PATH
echo "Added ${ZIG_DIR} to PATH"

# Get Zig version
ZIG_VERSION=$($ZIG_EXECUTABLE version)

echo "✅ Zig OHOS installed successfully"
echo "📍 Platform: $OS"
echo "🏷️  Version: $ZIG_VERSION"
echo "📂 Path: $ZIG_DIR"

# Set GitHub Actions outputs
echo "zig-path=$ZIG_DIR" >> "${GITHUB_OUTPUT}"
echo "zig-version=$ZIG_VERSION" >> "${GITHUB_OUTPUT}"
echo "platform=$OS" >> "${GITHUB_OUTPUT}"