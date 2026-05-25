#!/usr/bin/env bash

set -eux

: "${INPUT_TAG:?INPUT_TAG needs to be set}"
: "${INPUT_CACHE:?INPUT_CACHE needs to be set}"

# Base URL for Zig OHOS releases
URL_BASE="https://github.com/openharmony-zig/zig-patch/releases/download"

# Determine platform and set OS_FILENAME
if [[ "$OSTYPE" == "linux-musl"* ]]; then
    OS_FILENAME="zig-x86_64-linux-musl-baseline.tar.gz"
    OS="linux-musl"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS_FILENAME="zig-x86_64-linux-gnu-baseline.tar.gz"
    OS="linux-gnu"
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

to_actions_path() {
    local path="$1"

    if [[ "$OS" == "windows" ]]; then
        if command -v cygpath >/dev/null 2>&1; then
            cygpath -w "$path"
            return
        fi

        if [[ "$path" =~ ^/([a-zA-Z])/(.*)$ ]]; then
            local drive
            drive=$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:lower:]' '[:upper:]')
            printf '%s:\\%s\n' "$drive" "${BASH_REMATCH[2]//\//\\}"
            return
        fi
    fi

    printf '%s\n' "$path"
}

export_zig_to_actions() {
    local zig_dir="$1"
    local zig_version="$2"
    local zig_dir_for_actions
    zig_dir_for_actions=$(to_actions_path "$zig_dir")

    # Windows runners may continue in pwsh, which does not understand MSYS paths.
    printf '%s\n' "$zig_dir_for_actions" >> "$GITHUB_PATH"
    echo "Added ${zig_dir_for_actions} to PATH"

    printf 'zig-path=%s\n' "$zig_dir_for_actions" >> "${GITHUB_OUTPUT}"
    printf 'zig-version=%s\n' "$zig_version" >> "${GITHUB_OUTPUT}"
    printf 'platform=%s\n' "$OS" >> "${GITHUB_OUTPUT}"
}

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
        
        # get version and set output
        if [[ -f "${ZIG_DIR}/zig" ]]; then
            ZIG_VERSION=$(${ZIG_DIR}/zig version)
        else
            ZIG_VERSION=$(${ZIG_DIR}/zig.exe version)
        fi

        export_zig_to_actions "$ZIG_DIR" "$ZIG_VERSION"
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
tar -xf "zig-ohos.tar.gz"

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

# Set the executable path based on platform
if [[ "$OS" == "windows" ]]; then
    ZIG_EXECUTABLE="${ZIG_DIR}/zig.exe"
else
    ZIG_EXECUTABLE="${ZIG_DIR}/zig"
fi

# Clean up the archive
rm "zig-ohos.tar.gz"

# Make sure the executable is executable (for Unix-like systems)
if [[ "$OS" != "windows" ]]; then
    chmod +x "$ZIG_EXECUTABLE"
fi

# Get Zig version
ZIG_VERSION=$($ZIG_EXECUTABLE version)

export_zig_to_actions "$ZIG_DIR" "$ZIG_VERSION"

echo "✅ Zig OHOS installed successfully"
echo "📍 Platform: $OS"
echo "🏷️  Version: $ZIG_VERSION"
echo "📂 Path: $(to_actions_path "$ZIG_DIR")"
