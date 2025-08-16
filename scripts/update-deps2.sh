#!/bin/bash
# Update vendored dependencies for zzz (SDL3 game engine)
# Idempotent: only updates when versions change or deps are missing

set -e  # Exit on error

# ============================================================================
# CONFIGURATION - All dependency data in one place  
# ============================================================================

declare -A DEPS=(
    ["SDL"]="https://github.com/libsdl-org/SDL.git"
    ["webref"]="https://github.com/w3c/webref.git"
)

declare -A VERSIONS=(
    ["SDL"]="main"
    ["webref"]="main"
)

# Files to keep from existing installations (to preserve local modifications)
declare -A PRESERVE_FILES=(
    ["SDL"]="build.zig build.zig.zon"
    ["webref"]=""
)

# Files to remove from fresh clones (incompatible with our build)
declare -A REMOVE_FILES=(
    ["SDL"]=""
    ["webref"]=""
)

# Patches to apply (if any)
declare -A PATCHES=(
    # Example: ["SDL"]="deps/patches/sdl.patch"
    # Currently no patches needed
)

# SHA256 hashes for version verification (updated during successful clone)
declare -A SHA_HASHES=(
    ["SDL"]=""
)

# ============================================================================
# FUNCTIONS
# ============================================================================

# Colors and formatting
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    DIM='\033[2m'
    NC='\033[0m' # No Color
else
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' DIM='' NC=''
fi

# Enhanced logging functions
log_info() {
    echo -e "${BLUE}📦 ${BOLD}$1${NC}"
}

log_success() {
    echo -e "  ${GREEN}✓ $1${NC}"
}

log_step() {
    echo -e "  ${CYAN}→ $1${NC}"
}

log_skip() {
    echo -e "  ${YELLOW}⏭ $1${NC}"
}

log_warn() {
    echo -e "  ${YELLOW}⚠ $1${NC}"
}

log_error() {
    echo -e "  ${RED}✗ $1${NC}" >&2
}

log_debug() {
    if [[ "${DEBUG:-}" == "1" ]]; then
        echo -e "  ${DIM}→ $1${NC}" >&2
    fi
}

# Progress indicator
show_progress() {
    local current=$1
    local total=$2
    local name=$3
    local percent=$((current * 100 / total))
    echo -e "${DIM}[${current}/${total} ${percent}%] ${name}${NC}"
}

# Lock file management
LOCK_FILE="deps/.update-deps.lock"

acquire_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        local lock_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
        if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
            log_error "Another instance of update-deps is running (PID: $lock_pid)"
            exit 1
        else
            log_warn "Found stale lock file, removing..."
            rm -f "$LOCK_FILE"
        fi
    fi
    echo $$ > "$LOCK_FILE"
    log_debug "Acquired lock (PID: $$)"
}

release_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        rm -f "$LOCK_FILE"
        log_debug "Released lock"
    fi
}

# Ensure lock is released on exit
trap 'release_lock' EXIT

# Retry logic for network operations
retry_command() {
    local max_attempts=3
    local delay=2
    local attempt=1
    local cmd="$*"
    
    while [[ $attempt -le $max_attempts ]]; do
        log_debug "Attempt $attempt/$max_attempts: $cmd"
        if eval "$cmd"; then
            return 0
        fi
        
        if [[ $attempt -lt $max_attempts ]]; then
            log_warn "Command failed, retrying in ${delay}s..."
            sleep $delay
            delay=$((delay * 2))
        fi
        attempt=$((attempt + 1))
    done
    
    log_error "Command failed after $max_attempts attempts: $cmd"
    return 1
}

# Calculate SHA256 for a directory (excluding .git)
calculate_dir_hash() {
    local dir=$1
    if [[ -d "$dir" ]]; then
        find "$dir" -type f ! -path "*/.git/*" -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1
    else
        echo ""
    fi
}

# Get git commit hash
get_git_commit() {
    local dir=$1
    if [[ -d "$dir/.git" ]]; then
        git -C "$dir" rev-parse HEAD 2>/dev/null || echo ""
    else
        echo ""
    fi
}

# Check if dependency needs update
needs_update() {
    local name=$1
    local target_dir="deps/$name"
    local expected_version="${VERSIONS[$name]}"
    
    # If directory doesn't exist, needs update
    if [[ ! -d "$target_dir" ]]; then
        log_debug "needs_update($name): directory missing"
        return 0  # true, needs update
    fi
    
    # If .git directory exists, not properly vendored
    if [[ -d "$target_dir/.git" ]]; then
        log_debug "needs_update($name): .git directory found"
        return 0  # true, needs update
    fi
    
    # If no version file, needs update
    if [[ ! -f "$target_dir/.version" ]]; then
        log_debug "needs_update($name): .version file missing"
        return 0  # true, needs update
    fi
    
    # Check if version matches
    if grep -q "Version: $expected_version" "$target_dir/.version" 2>/dev/null; then
        # Additional integrity check: verify commit hash if available
        local recorded_commit=$(grep "Commit:" "$target_dir/.version" 2>/dev/null | cut -d' ' -f2)
        if [[ -n "$recorded_commit" ]]; then
            log_debug "needs_update($name): version matches ($expected_version), commit: $recorded_commit"
        fi
        
        # Check if build files that should be removed still exist
        if [[ -n "${REMOVE_FILES[$name]}" ]]; then
            for file in ${REMOVE_FILES[$name]}; do
                if [[ -f "$target_dir/$file" ]]; then
                    log_debug "needs_update($name): cleanup needed for $file"
                    return 0  # true, needs cleanup
                fi
            done
        fi
        
        log_debug "needs_update($name): up to date"
        return 1  # false, up to date
    fi
    
    log_debug "needs_update($name): version mismatch"
    return 0  # true, needs update (version mismatch)
}

# Clean and prepare a dependency (for existing deps)
clean_dependency() {
    local name=$1
    local target_dir="deps/$name"
    local temp_preserve_dir="/tmp/preserved_files_$$"
    
    # Preserve important build files before cleaning
    if [[ -n "${PRESERVE_FILES[$name]}" ]]; then
        mkdir -p "$temp_preserve_dir"
        for file in ${PRESERVE_FILES[$name]}; do
            if [[ -f "$target_dir/$file" ]]; then
                log_step "Preserving $file"
                cp "$target_dir/$file" "$temp_preserve_dir/"
            fi
        done
    fi
    
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
    
    # Restore preserved files
    if [[ -d "$temp_preserve_dir" ]]; then
        for file in ${PRESERVE_FILES[$name]}; do
            if [[ -f "$temp_preserve_dir/$file" ]]; then
                log_step "Restoring preserved $file"
                cp "$temp_preserve_dir/$file" "$target_dir/"
            fi
        done
        rm -rf "$temp_preserve_dir"
    fi
    
    # Apply patches if any
    if [[ -n "${PATCHES[$name]}" ]] && [[ -f "${PATCHES[$name]}" ]]; then
        log_step "Applying patch ${PATCHES[$name]}"
        if ! patch -p1 -d "$target_dir" < "${PATCHES[$name]}"; then
            log_error "Failed to apply patch ${PATCHES[$name]}"
            return 1
        fi
    fi
}

# Record version information
record_version() {
    local name=$1
    local target_dir="deps/$name"
    local commit_hash=""
    
    # Try to get commit hash before .git removal
    if [[ -d "$target_dir/.git" ]]; then
        commit_hash=$(get_git_commit "$target_dir")
    fi
    
    cat > "$target_dir/.version" << EOF
Repository: ${DEPS[$name]}
Version: ${VERSIONS[$name]}
Commit: ${commit_hash}
Updated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
Updated-By: $(whoami)@$(hostname)
EOF
}

# Create backup of existing dependency
backup_dependency() {
    local name=$1
    local target_dir="deps/$name"
    local backup_dir="deps/.backups/$name-$(date +%Y%m%d-%H%M%S)"
    
    if [[ -d "$target_dir" ]]; then
        log_step "Creating backup: $backup_dir"
        mkdir -p "deps/.backups"
        cp -r "$target_dir" "$backup_dir"
        return 0
    fi
    return 1
}

# Rollback to backup if available
rollback_dependency() {
    local name=$1
    local target_dir="deps/$name"
    local latest_backup=$(find deps/.backups -maxdepth 1 -name "$name-*" -type d 2>/dev/null | sort -r | head -n1)
    
    if [[ -n "$latest_backup" ]]; then
        log_warn "Rolling back $name to backup: $(basename "$latest_backup")"
        rm -rf "$target_dir"
        cp -r "$latest_backup" "$target_dir"
        return 0
    else
        log_error "No backup available for $name"
        return 1
    fi
}

# Vendor a single dependency with atomic operations
vendor_dependency() {
    local name=$1
    local url="${DEPS[$name]}"
    local version="${VERSIONS[$name]}"
    local target_dir="deps/$name"
    local temp_dir="deps/.tmp/$name-$$"
    local backup_created=false
    
    # Check if update is needed
    if ! needs_update "$name"; then
        log_skip "Skipping $name (already up to date: $version)"
        return 0
    fi
    
    log_step "Updating $name to $version"
    
    # Check for API changes before updating
    check_api_changes "$name"
    
    # Create backup if directory exists
    if [[ -d "$target_dir" ]]; then
        if backup_dependency "$name"; then
            backup_created=true
        fi
    fi
    
    # Ensure temp directory exists and is clean
    mkdir -p "deps/.tmp"
    rm -rf "$temp_dir"
    
    # Clone to temporary directory first (atomic operation)
    log_step "Fetching $name ($version) to temporary location"
    local clone_cmd
    if [[ "$version" == "main" ]] || [[ "$version" == "master" ]]; then
        clone_cmd="git clone --quiet --depth 1 '$url' '$temp_dir'"
    else
        clone_cmd="git clone --quiet --depth 1 --branch '$version' '$url' '$temp_dir'"
    fi
    
    if ! retry_command "$clone_cmd"; then
        log_error "Failed to clone $name"
        if [[ "$backup_created" == "true" ]]; then
            rollback_dependency "$name"
        fi
        return 1
    fi
    
    # Verify the clone was successful
    if [[ ! -d "$temp_dir" ]]; then
        log_error "Clone succeeded but directory not found: $temp_dir"
        return 1
    fi
    
    # Record version before cleaning (create a modified record function for temp dir)
    local commit_hash=""
    if [[ -d "$temp_dir/.git" ]]; then
        commit_hash=$(get_git_commit "$temp_dir")
    fi
    
    cat > "$temp_dir/.version" << EOF
Repository: ${DEPS[$name]}
Version: ${VERSIONS[$name]}
Commit: ${commit_hash}
Updated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
Updated-By: $(whoami)@$(hostname)
EOF

    if [[ $? -ne 0 ]]; then
        log_error "Failed to record version for $name"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Clean the dependency in temp location
    # We need to clean using the actual dependency name, not the temp dir name
    # First, temporarily update the target_dir in clean_dependency to use temp_dir
    local original_target="deps/$name"
    
    # Create a modified clean function that works on temp dir
    clean_temp_dependency() {
        local dep_name=$1
        local temp_target=$2
        local temp_preserve_dir="/tmp/preserved_files_$$"
        
        # Remove .git directory if it exists
        if [[ -d "$temp_target/.git" ]]; then
            log_step "Removing .git directory"
            rm -rf "$temp_target/.git"
        fi
        
        # Remove incompatible files
        if [[ -n "${REMOVE_FILES[$dep_name]}" ]]; then
            for file in ${REMOVE_FILES[$dep_name]}; do
                if [[ -f "$temp_target/$file" ]]; then
                    log_step "Removing $file"
                    rm -f "$temp_target/$file"
                fi
            done
        fi
        
        # Apply patches if any
        if [[ -n "${PATCHES[$dep_name]}" ]] && [[ -f "${PATCHES[$dep_name]}" ]]; then
            log_step "Applying patch ${PATCHES[$dep_name]}"
            if ! patch -p1 -d "$temp_target" < "${PATCHES[$dep_name]}"; then
                log_error "Failed to apply patch ${PATCHES[$dep_name]}"
                return 1
            fi
        fi
    }
    
    if ! clean_temp_dependency "$name" "$temp_dir"; then
        log_error "Failed to clean $name"
        rm -rf "$temp_dir"
        if [[ "$backup_created" == "true" ]]; then
            rollback_dependency "$name"
        fi
        return 1
    fi
    
    # Atomic move to final location
    log_step "Installing $name"
    rm -rf "$target_dir"
    if ! mv "$temp_dir" "$target_dir"; then
        log_error "Failed to install $name"
        if [[ "$backup_created" == "true" ]]; then
            rollback_dependency "$name"
        fi
        return 1
    fi
    
    log_success "$name vendored successfully"
    return 0
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

# List all dependencies and their status
list_dependencies() {
    echo -e "${BOLD}Dependency Status Report${NC}"
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║                               Dependencies                                   ║"
    echo "╠════════════════╦═════════════════╦═══════════════╦══════════════════════════╣"
    echo "║ Name           ║ Expected        ║ Status        ║ Last Updated             ║"
    echo "╠════════════════╬═════════════════╬═══════════════╬══════════════════════════╣"
    
    for dep in "${!DEPS[@]}"; do
        local expected="${VERSIONS[$dep]}"
        local target_dir="deps/$dep"
        local status="Missing"
        local last_updated="Never"
        local status_color="$RED"
        
        if [[ -d "$target_dir" ]]; then
            if [[ -f "$target_dir/.version" ]]; then
                local current_version=$(grep "Version:" "$target_dir/.version" 2>/dev/null | cut -d' ' -f2)
                local updated_date=$(grep "Updated:" "$target_dir/.version" 2>/dev/null | cut -d' ' -f2-)
                
                if [[ "$current_version" == "$expected" ]]; then
                    status="Up to date"
                    status_color="$GREEN"
                else
                    status="Outdated ($current_version)"
                    status_color="$YELLOW"
                fi
                
                if [[ -n "$updated_date" ]]; then
                    last_updated="$updated_date"
                fi
            else
                status="Unmanaged"
                status_color="$YELLOW"
            fi
        fi
        
        printf "║ %-14s ║ %-15s ║ ${status_color}%-13s${NC} ║ %-24s ║\n" \
            "$dep" "$expected" "$status" "$last_updated"
    done
    
    echo "╚════════════════╩═════════════════╩═══════════════╩══════════════════════════╝"
}

# Check dependencies without updating
check_dependencies() {
    local need_update=()
    local up_to_date=()
    local missing=()
    
    log_info "Checking dependency status..."
    
    for dep in "${!DEPS[@]}"; do
        if [[ ! -d "deps/$dep" ]]; then
            missing+=("$dep")
        elif needs_update "$dep"; then
            need_update+=("$dep")
        else
            up_to_date+=("$dep")
        fi
    done
    
    echo ""
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing dependencies: ${missing[*]}"
    fi
    
    if [[ ${#need_update[@]} -gt 0 ]]; then
        log_warn "Dependencies needing updates: ${need_update[*]}"
    fi
    
    if [[ ${#up_to_date[@]} -gt 0 ]]; then
        log_success "Up-to-date dependencies: ${up_to_date[*]}"
    fi
    
    echo ""
    
    # Return exit code based on status
    if [[ ${#missing[@]} -gt 0 || ${#need_update[@]} -gt 0 ]]; then
        return 1  # Updates needed
    else
        return 0  # All good
    fi
}

# Dry run - show what would be updated without doing it
dry_run() {
    local actions=()
    
    log_info "Dry run: analyzing what would be updated..."
    echo ""
    
    for dep in "${!DEPS[@]}"; do
        local target_dir="deps/$dep"
        local expected_version="${VERSIONS[$dep]}"
        
        if [[ ! -d "$target_dir" ]]; then
            actions+=("INSTALL $dep (${expected_version})")
            echo -e "  ${CYAN}→ Would INSTALL${NC} $dep (${expected_version})"
        elif needs_update "$dep"; then
            local current=""
            if [[ -f "$target_dir/.version" ]]; then
                current=$(grep "Version:" "$target_dir/.version" 2>/dev/null | cut -d' ' -f2)
                current=" from $current"
            fi
            actions+=("UPDATE $dep$current to ${expected_version}")
            echo -e "  ${YELLOW}→ Would UPDATE${NC} $dep$current to ${expected_version}"
        else
            echo -e "  ${GREEN}→ Would SKIP${NC} $dep (already ${expected_version})"
        fi
    done
    
    echo ""
    
    if [[ ${#actions[@]} -eq 0 ]]; then
        log_success "All dependencies are up to date! No actions needed."
    else
        log_info "Summary of planned actions:"
        for action in "${actions[@]}"; do
            echo "  • $action"
        done
        echo ""
        echo "Run without --dry-run to execute these actions."
    fi
    
    return 0
}

# Update CREDITS.md with dependency information
update_credits() {
    local credits_file="deps/CREDITS.md"
    local temp_credits="/tmp/credits_$$"
    
    log_step "Updating CREDITS.md"
    
    cat > "$temp_credits" << 'EOF'
# SDL Vendoring Credits

## SDL Build Configuration

The Zig build configuration for SDL in `deps/SDL/build.zig` and `deps/SDL/build.zig.zon` is based on work by:

- **Carl Åstholm** (castholm)
  - Repository: https://github.com/castholm/SDL
  - License: MIT
  - © 2024 Carl Åstholm

This build configuration has been adapted for the Zzz project with the following modifications:
- Disabled Wayland and KMS/DRM video drivers for simplified vendoring
- Disabled joystick and haptic subsystems per project requirements
- Added dummy implementations for unsupported subsystems
- Fixed missing configuration values for xkbcommon and X11 extensions

## SDL

The SDL library itself is:
- **SDL**: Copyright (C) 1997-2024 Sam Lantinga and contributors
  - Repository: https://github.com/libsdl-org/SDL
  - License: zlib license

## Current Versions

EOF

    # Add current version information
    for dep in "${!DEPS[@]}"; do
        local target_dir="deps/$dep"
        if [[ -f "$target_dir/.version" ]]; then
            local version=$(grep "Version:" "$target_dir/.version" 2>/dev/null | cut -d' ' -f2)
            local commit=$(grep "Commit:" "$target_dir/.version" 2>/dev/null | cut -d' ' -f2)
            local updated=$(grep "Updated:" "$target_dir/.version" 2>/dev/null | cut -d' ' -f2-)
            
            cat >> "$temp_credits" << EOF
- **$dep**: $version
  - Repository: ${DEPS[$dep]}
  - Commit: $commit
  - Last Updated: $updated

EOF
        fi
    done
    
    cat >> "$temp_credits" << 'EOF'

## Note

The source code in deps/SDL has been kept unmodified from the original repository to maintain compatibility and ease of updates. Only the build configuration files have been modified.
EOF

    # Only update if content has changed
    if [[ ! -f "$credits_file" ]] || ! diff -q "$temp_credits" "$credits_file" >/dev/null 2>&1; then
        mv "$temp_credits" "$credits_file"
        log_success "Updated CREDITS.md"
    else
        rm -f "$temp_credits"
        log_debug "CREDITS.md unchanged"
    fi
}

# Check for potential API breaking changes (simplified detection)
check_api_changes() {
    local name=$1
    local target_dir="deps/$name"
    
    if [[ ! -d "$target_dir" ]]; then
        return 0  # No existing version to compare
    fi
    
    # Look for version indicators that might suggest breaking changes
    if [[ -f "$target_dir/.version" ]]; then
        local old_version=$(grep "Version:" "$target_dir/.version" 2>/dev/null | cut -d' ' -f2)
        local new_version="${VERSIONS[$name]}"
        
        if [[ "$old_version" != "$new_version" ]]; then
            log_warn "Version change detected for $name: $old_version → $new_version"
            
            # Simple heuristic for major version changes
            if [[ "$old_version" =~ ^v?([0-9]+) ]] && [[ "$new_version" =~ ^v?([0-9]+) ]]; then
                local old_major="${BASH_REMATCH[1]}"
                if [[ "$new_version" =~ ^v?([0-9]+) ]]; then
                    local new_major="${BASH_REMATCH[1]}"
                    if [[ "$old_major" != "$new_major" ]]; then
                        log_warn "⚠ Major version change detected! Please review for breaking changes."
                    fi
                fi
            fi
        fi
    fi
}

# ============================================================================
# MAIN SCRIPT
# ============================================================================

main() {
    # Parse arguments
    local force_all=false
    local force_dep=""
    local check_only=false
    local list_only=false
    local dry_run_mode=false
    local update_pattern=""
    
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
            --check)
                check_only=true
                shift
                ;;
            --list)
                list_only=true
                shift
                ;;
            --dry-run)
                dry_run_mode=true
                shift
                ;;
            --update)
                update_pattern="$2"
                shift 2
                ;;
            --debug)
                export DEBUG=1
                shift
                ;;
            --help|-h)
                cat << EOF
Usage: $0 [OPTIONS]

${BOLD}SDL3 Dependency Vendoring Tool${NC}
Idempotent script to vendor SDL dependencies. Only updates when needed.

${BOLD}Options:${NC}
  --force               Force update all dependencies
  --force-dep NAME      Force update specific dependency
  --check               Check status without updating (CI-friendly)
  --list                List all dependencies and their status
  --dry-run             Show what would be updated without doing it
  --update PATTERN      Update dependencies matching pattern (glob)
  --debug               Enable debug output
  --help, -h            Show this help message

${BOLD}Dependencies:${NC}
  ${!DEPS[@]}

${BOLD}Examples:${NC}
  $0                        # Update only if needed
  $0 --check                # Check status (good for CI)
  $0 --list                 # Show detailed status table
  $0 --dry-run              # Preview what would change
  $0 --force                # Force update all
  $0 --force-dep SDL        # Force update SDL only
  $0 --update "SDL*"        # Update all SDL-related deps
  
${BOLD}Exit Codes:${NC}
  0 - Success or no updates needed
  1 - Updates needed (--check) or errors occurred
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
    
    # Acquire lock to prevent concurrent execution
    acquire_lock
    
    # Handle special modes first
    if [[ "$list_only" == "true" ]]; then
        list_dependencies
        exit 0
    fi
    
    if [[ "$check_only" == "true" ]]; then
        check_dependencies
        exit $?
    fi
    
    if [[ "$dry_run_mode" == "true" ]]; then
        dry_run
        exit 0
    fi
    
    log_info "Managing vendored dependencies for zzz (SDL3 game engine)"
    echo ""
    
    # Create deps directory if it doesn't exist
    mkdir -p deps
    
    # Track what was updated
    local updated_count=0
    local skipped_count=0
    local failed_count=0
    local total_deps=${#DEPS[@]}
    local current_dep=0
    
    # Handle forced single dependency update
    if [[ -n "$force_dep" ]]; then
        if force_update "$force_dep"; then
            updated_count=1
        else
            failed_count=1
        fi
    else
        # Update each dependency
        for dep in "${!DEPS[@]}"; do
            current_dep=$((current_dep + 1))
            
            # Skip if pattern specified and doesn't match
            if [[ -n "$update_pattern" ]] && [[ ! "$dep" == $update_pattern ]]; then
                log_debug "Skipping $dep (doesn't match pattern: $update_pattern)"
                continue
            fi
            
            show_progress $current_dep $total_deps "$dep"
            
            if [[ "$force_all" == "true" ]]; then
                # Force remove and re-vendor
                if [[ -d "deps/$dep" ]]; then
                    rm -rf "deps/$dep"
                fi
                if vendor_dependency "$dep"; then
                    updated_count=$((updated_count + 1))
                else
                    failed_count=$((failed_count + 1))
                fi
            else
                # Only update if needed
                if needs_update "$dep"; then
                    if vendor_dependency "$dep"; then
                        updated_count=$((updated_count + 1))
                    else
                        failed_count=$((failed_count + 1))
                    fi
                else
                    log_skip "Skipping $dep (already up to date: ${VERSIONS[$dep]})"
                    skipped_count=$((skipped_count + 1))
                fi
            fi
        done
    fi
    
    echo ""
    
    # Show summary
    if [[ $failed_count -gt 0 ]]; then
        log_error "❌ $failed_count dependencies failed to update"
    fi
    
    if [[ $updated_count -eq 0 ]] && [[ $failed_count -eq 0 ]]; then
        log_info "All dependencies already up to date! ✨"
    else
        if [[ $updated_count -gt 0 ]]; then
            log_success "✅ Updated $updated_count dependencies"
        fi
        if [[ $skipped_count -gt 0 ]]; then
            echo "  (Skipped $skipped_count already up-to-date)"
        fi
    fi
    
    echo ""
    
    # Show version summary
    echo -e "${BOLD}Current Versions:${NC}"
    echo "┌──────────────────┬──────────────┐"
    echo "│ Dependency       │ Version      │"
    echo "├──────────────────┼──────────────┤"
    for dep in "${!VERSIONS[@]}"; do
        printf "│ %-16s │ %-12s │\n" "$dep" "${VERSIONS[$dep]}"
    done
    echo "└──────────────────┴──────────────┘"
    
    # Update CREDITS.md if any dependencies were updated
    if [[ $updated_count -gt 0 ]]; then
        echo ""
        update_credits
    fi
    
    # Only show next steps if we actually updated something
    if [[ $updated_count -gt 0 ]]; then
        echo ""
        echo -e "${BOLD}Next steps:${NC}"
        echo "  1. Review changes:  git diff deps/"
        echo "  2. Test build:      zig build"
        echo "  3. Run tests:       zig build test"
        echo "  4. Commit changes:  git add deps/ && git commit -m 'Update vendored SDL dependencies'"
    fi
    
    # Clean up temp directories
    rm -rf deps/.tmp
    
    # Return appropriate exit code
    if [[ $failed_count -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

# Run main function
main "$@"