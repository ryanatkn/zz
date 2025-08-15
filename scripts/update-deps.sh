#!/bin/bash
# Update vendored dependencies for zz
# Idempotent: only updates when versions change or deps are missing

set -e  # Exit on error

# ============================================================================
# CONFIGURATION - All dependency data in one place
# ============================================================================

declare -A DEPS=(
    ["tree-sitter"]="https://github.com/tree-sitter/tree-sitter.git"
    ["zig-tree-sitter"]="https://github.com/tree-sitter/zig-tree-sitter.git"
    ["tree-sitter-zig"]="https://github.com/maxxnino/tree-sitter-zig.git"
    ["zig-spec"]="https://github.com/ziglang/zig-spec.git"
    ["tree-sitter-svelte"]="https://github.com/tree-sitter-grammars/tree-sitter-svelte.git"
    ["tree-sitter-css"]="https://github.com/tree-sitter/tree-sitter-css.git"
    ["tree-sitter-typescript"]="https://github.com/tree-sitter/tree-sitter-typescript.git"
    ["tree-sitter-json"]="https://github.com/tree-sitter/tree-sitter-json.git"
    ["tree-sitter-html"]="https://github.com/tree-sitter/tree-sitter-html.git"
)

declare -A VERSIONS=(
    ["tree-sitter"]="v0.25.0"
    ["zig-tree-sitter"]="v0.25.0"
    ["tree-sitter-zig"]="main"
    ["zig-spec"]="main"
    ["tree-sitter-svelte"]="v1.0.2"
    ["tree-sitter-css"]="v0.23.0"
    ["tree-sitter-typescript"]="v0.23.2"
    ["tree-sitter-json"]="v0.24.8"
    ["tree-sitter-html"]="v0.23.0"
)

# Files to remove from each dependency (incompatible with our build)
declare -A REMOVE_FILES=(
    ["tree-sitter"]="build.zig build.zig.zon"
    ["zig-tree-sitter"]="build.zig build.zig.zon"
    ["tree-sitter-zig"]="build.zig build.zig.zon"
    ["zig-spec"]=""
    ["tree-sitter-svelte"]="build.zig build.zig.zon"
    ["tree-sitter-css"]="build.zig build.zig.zon"
    ["tree-sitter-typescript"]="build.zig build.zig.zon"
    ["tree-sitter-json"]="build.zig build.zig.zon"
    ["tree-sitter-html"]="build.zig build.zig.zon"
)

# Patches to apply (if any)
declare -A PATCHES=(
    # Example: ["tree-sitter"]="deps/patches/tree-sitter.patch"
    # Currently no patches needed for v0.25.0
)

# ============================================================================
# FUNCTIONS
# ============================================================================

log_info() {
    echo "📦 $1"
}

log_success() {
    echo "  ✓ $1"
}

log_step() {
    echo "  → $1"
}

log_skip() {
    echo "  ⏭ $1"
}

# Check if dependency needs update
needs_update() {
    local name=$1
    local target_dir="deps/$name"
    local expected_version="${VERSIONS[$name]}"
    
    # If directory doesn't exist, needs update
    if [[ ! -d "$target_dir" ]]; then
        return 0  # true, needs update
    fi
    
    # If .git directory exists, not properly vendored
    if [[ -d "$target_dir/.git" ]]; then
        return 0  # true, needs update
    fi
    
    # If no version file, needs update
    if [[ ! -f "$target_dir/.version" ]]; then
        return 0  # true, needs update
    fi
    
    # Check if version matches
    if grep -q "Version: $expected_version" "$target_dir/.version" 2>/dev/null; then
        # Check if build files that should be removed still exist
        if [[ -n "${REMOVE_FILES[$name]}" ]]; then
            for file in ${REMOVE_FILES[$name]}; do
                if [[ -f "$target_dir/$file" ]]; then
                    return 0  # true, needs cleanup
                fi
            done
        fi
        return 1  # false, up to date
    fi
    
    return 0  # true, needs update (version mismatch)
}

# Clean and prepare a dependency (for existing deps)
clean_dependency() {
    local name=$1
    local target_dir="deps/$name"
    
    # Remove .git directory if it exists
    if [[ -d "$target_dir/.git" ]]; then
        log_step "Removing .git directory"
        rm -rf "$target_dir/.git"
    fi
    
    # Remove incompatible files
    if [[ -n "${REMOVE_FILES[$name]}" ]]; then
        for file in ${REMOVE_FILES[$name]}; do
            if [[ -f "$target_dir/$file" ]]; then
                log_step "Removing $file"
                rm -f "$target_dir/$file"
            fi
        done
    fi
    
    # Apply patches if any
    if [[ -n "${PATCHES[$name]}" ]] && [[ -f "${PATCHES[$name]}" ]]; then
        log_step "Applying patch ${PATCHES[$name]}"
        patch -p1 -d "$target_dir" < "${PATCHES[$name]}"
    fi
}

# Record version information
record_version() {
    local name=$1
    local target_dir="deps/$name"
    
    cat > "$target_dir/.version" << EOF
Repository: ${DEPS[$name]}
Version: ${VERSIONS[$name]}
Updated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
EOF
}

# Vendor a single dependency
vendor_dependency() {
    local name=$1
    local url="${DEPS[$name]}"
    local version="${VERSIONS[$name]}"
    local target_dir="deps/$name"
    
    # Check if update is needed
    if ! needs_update "$name"; then
        log_skip "Skipping $name (already up to date: $version)"
        return 0
    fi
    
    log_step "Updating $name to $version"
    
    # Remove existing directory if it exists
    if [[ -d "$target_dir" ]]; then
        log_step "Removing old version"
        rm -rf "$target_dir"
    fi
    
    # Clone specific version
    log_step "Fetching $name ($version)"
    if [[ "$version" == "main" ]] || [[ "$version" == "master" ]]; then
        git clone --quiet --depth 1 "$url" "$target_dir" 2>/dev/null
    else
        git clone --quiet --depth 1 --branch "$version" "$url" "$target_dir" 2>/dev/null
    fi
    
    # Record version before cleaning
    record_version "$name"
    
    # Clean the dependency
    clean_dependency "$name"
    
    log_success "$name vendored successfully"
}

# Force update a specific dependency
force_update() {
    local name=$1
    
    if [[ -z "${DEPS[$name]}" ]]; then
        echo "Error: Unknown dependency '$name'"
        echo "Available dependencies: ${!DEPS[@]}"
        return 1
    fi
    
    local target_dir="deps/$name"
    
    log_info "Force updating $name"
    
    # Remove existing directory
    if [[ -d "$target_dir" ]]; then
        rm -rf "$target_dir"
    fi
    
    # Vendor it
    vendor_dependency "$name"
}

# ============================================================================
# MAIN SCRIPT
# ============================================================================

main() {
    # Parse arguments
    local force_all=false
    local force_dep=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                force_all=true
                shift
                ;;
            --force-dep)
                force_dep="$2"
                shift 2
                ;;
            --help|-h)
                cat << EOF
Usage: $0 [OPTIONS]

Idempotent script to vendor dependencies. Only updates when needed.

Options:
  --force           Force update all dependencies
  --force-dep NAME  Force update specific dependency
  --help, -h        Show this help message

Dependencies:
  ${!DEPS[@]}

Examples:
  $0                           # Update only if needed
  $0 --force                   # Force update all
  $0 --force-dep tree-sitter   # Force update tree-sitter only
EOF
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    log_info "Checking vendored dependencies for zz"
    echo ""
    
    # Create deps directory if it doesn't exist
    mkdir -p deps
    
    # Track what was updated
    local updated_count=0
    local skipped_count=0
    
    # Handle forced single dependency update
    if [[ -n "$force_dep" ]]; then
        force_update "$force_dep"
        updated_count=1
    else
        # Update each dependency
        for dep in "${!DEPS[@]}"; do
            if [[ "$force_all" == "true" ]]; then
                # Force remove and re-vendor
                if [[ -d "deps/$dep" ]]; then
                    rm -rf "deps/$dep"
                fi
                vendor_dependency "$dep"
                updated_count=$((updated_count + 1))
            else
                # Only update if needed
                if needs_update "$dep"; then
                    vendor_dependency "$dep"
                    updated_count=$((updated_count + 1))
                else
                    log_skip "Skipping $dep (already up to date: ${VERSIONS[$dep]})"
                    skipped_count=$((skipped_count + 1))
                fi
            fi
        done
    fi
    
    echo ""
    
    # Show summary
    if [[ $updated_count -eq 0 ]]; then
        log_info "All dependencies already up to date! ✨"
    else
        log_info "Updated $updated_count dependencies"
        if [[ $skipped_count -gt 0 ]]; then
            echo "  (Skipped $skipped_count already up-to-date)"
        fi
    fi
    
    echo ""
    
    # Show version summary
    echo "Current Versions:"
    echo "┌──────────────────┬──────────────┐"
    echo "│ Dependency       │ Version      │"
    echo "├──────────────────┼──────────────┤"
    for dep in "${!VERSIONS[@]}"; do
        printf "│ %-16s │ %-12s │\n" "$dep" "${VERSIONS[$dep]}"
    done
    echo "└──────────────────┴──────────────┘"
    
    # Only show next steps if we actually updated something
    if [[ $updated_count -gt 0 ]]; then
        echo ""
        echo "Next steps:"
        echo "  1. Review changes:  git diff deps/"
        echo "  2. Test build:      zig build test"
        echo "  3. Run benchmarks:  zig build benchmark"
        echo "  4. Commit:          git add deps/ && git commit -m 'Update vendored dependencies'"
    fi
}

# Run main function
main "$@"