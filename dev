#!/bin/bash

set -euo pipefail

# Change to script directory
cd "$(dirname "$0")"

# Build the project
if ! zig build; then
    echo "Build failed!" >&2
    exit 1
fi

# Run the binary with all arguments
exec ./zig-out/bin/zz "$@"