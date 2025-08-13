# zz Security Architecture and Guidelines

> **Archived:** Historical security document. References to `zz gather` represent concepts implemented in `zz prompt`.

## Security Philosophy

`zz` is designed with **security-first principles** for natural language programming environments where AI assistants have direct access to system commands. Every feature is evaluated through a security lens before implementation.

## Core Security Principles

### 1. Least Privilege by Design
- **Read-only by default:** All commands are read-only unless explicitly designed otherwise
- **Explicit permissions:** Write operations require explicit flags and confirmation
- **Scope limitations:** Commands operate within defined boundaries
- **Resource constraints:** Built-in limits prevent resource exhaustion

### 2. Defense in Depth
- **Input validation:** Comprehensive sanitization of all user inputs
- **Filesystem abstraction:** Parameterized dependencies prevent direct filesystem access
- **Memory safety:** Zig's compile-time safety prevents common vulnerabilities
- **Error handling:** Comprehensive error handling prevents information leakage

### 3. Secure by Default
- **No external dependencies:** Zero external libraries reduce attack surface
- **POSIX-only:** No Windows support reduces complexity and attack vectors
- **Filesystem sandboxing:** Mock filesystem for testing prevents test artifacts
- **Configuration validation:** All configuration is validated before use

## Security Architecture

### Command Classification System

#### Green Light Commands (No Security Risk)
**Characteristics:** Read-only, no side effects, bounded resource usage

```bash
# File system inspection
zz tree                          # Directory visualization
zz prompt "*.zig"               # File content aggregation

# Performance measurement  
zz benchmark                    # Performance testing

# Information gathering
zz gather "error patterns"      # Pattern collection
zz analyze security             # Static analysis
```

**Security Guarantees:**
- Cannot modify filesystem
- Cannot execute arbitrary code
- Cannot access network resources
- Memory usage bounded by configuration

#### Yellow Light Commands (Controlled Risk)
**Characteristics:** Transformation operations with safety mechanisms

```bash
# Pattern processing (proposed)
pp transform --dry-run --preview    # Safe transformation preview
mm link-check --fix-broken          # Link repair with validation

# Content transformation
ff transform json --to=yaml --validate  # Format conversion with validation
```

**Security Controls:**
- Preview mode mandatory for destructive operations
- Rollback capabilities for all modifications
- Explicit confirmation for write operations
- Comprehensive logging of all changes

#### Red Light Commands (Explicitly Avoided)
**Operations never implemented in `zz` ecosystem:**

```bash
# Forbidden operations
zz execute <command>            # Arbitrary command execution
zz network <url>               # Network operations
zz eval <code>                 # Dynamic code evaluation
zz shell                       # Shell access
```

### Filesystem Security Model

#### Abstraction Layer Benefits
```zig
// Production code uses real filesystem
const filesystem = RealFilesystem.init();
const result = tree.run(allocator, filesystem, args);

// Tests use mock filesystem - complete isolation
var mock_fs = MockFilesystem.init(allocator);
try mock_fs.addFile("test.zig", "const std = @import(\"std\");");
const result = tree.run(allocator, mock_fs.interface(), args);
```

**Security Advantages:**
- **Test isolation:** No test artifacts in working directory
- **Permission testing:** Simulate permission denied scenarios safely  
- **Error condition testing:** Test disk full, network errors without real impact
- **Malicious input testing:** Test with crafted inputs safely

#### Path Traversal Prevention
```zig
// Built-in path validation prevents directory traversal
pub fn validatePath(path: []const u8) !void {
    if (std.mem.indexOf(u8, path, "..") != null) {
        return error.PathTraversalAttempt;
    }
    if (path[0] == '/' and !isAllowedAbsolutePath(path)) {
        return error.UnauthorizedAbsolutePath;
    }
}
```

### Input Validation Framework

#### Pattern Sanitization
```zig
pub fn sanitizePattern(pattern: []const u8) ![]const u8 {
    // Remove potentially dangerous characters
    const dangerous_chars = &[_]u8{ ';', '|', '&', '$', '`' };
    
    for (dangerous_chars) |char| {
        if (std.mem.indexOf(u8, pattern, &[_]u8{char}) != null) {
            return error.DangerousCharacterInPattern;
        }
    }
    
    // Validate pattern syntax
    return validateGlobPattern(pattern);
}
```

#### Configuration Validation
```zig
pub fn validateConfig(config: *const ZonConfig) !void {
    // Validate ignore patterns
    for (config.ignored_patterns) |pattern| {
        try validatePattern(pattern);
    }
    
    // Ensure reasonable resource limits
    if (config.max_depth > MAX_SAFE_DEPTH) {
        return error.ExcessiveDepthLimit;
    }
    
    // Validate file size limits
    if (config.max_file_size > MAX_SAFE_FILE_SIZE) {
        return error.ExcessiveFileSizeLimit;
    }
}
```

## Threat Model

### Identified Threats

#### T1: Malicious Input Injection
**Risk:** High  
**Impact:** Code execution, data exfiltration  
**Mitigation:**
- Comprehensive input sanitization
- Whitelist-based validation
- No dynamic code evaluation
- Pattern syntax validation

#### T2: Path Traversal Attacks
**Risk:** Medium  
**Impact:** Unauthorized file access  
**Mitigation:**
- Path validation at multiple layers
- Canonical path resolution
- Filesystem abstraction boundaries
- Absolute path restrictions

#### T3: Resource Exhaustion (DoS)
**Risk:** Medium  
**Impact:** System unavailability  
**Mitigation:**
- Built-in resource limits
- Memory usage monitoring
- Time-based operation limits
- Graceful degradation

#### T4: Information Disclosure
**Risk:** Medium  
**Impact:** Sensitive data exposure  
**Mitigation:**
- Pattern-based file filtering
- Hidden file protection
- Error message sanitization
- Access control integration

#### T5: Configuration Tampering
**Risk:** Low  
**Impact:** Privilege escalation  
**Mitigation:**
- Configuration validation
- Checksum verification
- Safe default values
- User permission checks

### Attack Scenarios

#### Scenario 1: AI Assistant Compromise
**Description:** Malicious actor gains control of AI assistant with `zz` access

**Attack Vector:**
```bash
# Attempted malicious commands
zz tree ../../../etc/        # Path traversal attempt
zz prompt "*.key;rm -rf /"   # Command injection attempt
zz gather "$(malicious)"     # Variable expansion attempt
```

**Defense Mechanisms:**
- Path validation prevents traversal
- Input sanitization blocks injection
- No shell command evaluation
- Resource limits prevent exhaustive operations

#### Scenario 2: Malicious Project Files
**Description:** Crafted project with malicious configuration or file names

**Attack Vector:**
- Files with shell metacharacters in names
- Symlinks pointing to sensitive locations  
- Configuration files with malicious patterns
- Very large files causing memory exhaustion

**Defense Mechanisms:**
- Filename sanitization during processing
- Symlink handling configuration
- Configuration validation and limits
- Memory usage monitoring and limits

#### Scenario 3: Supply Chain Attack
**Description:** Compromise of build or distribution systems

**Mitigation:**
- Reproducible builds
- Minimal dependencies (zero external deps)
- Code signing and verification
- Source code transparency

## Security Configuration

### Default Security Settings
```zon
.{
    // Security-focused defaults
    .security = .{
        // Filesystem protection
        .max_file_size = "10MB",
        .max_depth = 20,
        .follow_symlinks = false,
        
        // Resource limits
        .max_memory_usage = "100MB",
        .max_execution_time = "30s",
        .max_files_processed = 10000,
        
        // Pattern restrictions
        .allow_shell_patterns = false,
        .allow_regex_patterns = false,
        .forbidden_chars = .{ `;`, `|`, `&`, `$`, ``` },
        
        // Access control
        .restricted_paths = .{ "/etc", "/proc", "/sys" },
        .allowed_extensions = .{ ".zig", ".md", ".txt", ".json" },
    },
}
```

### Claude Code Security Integration
```json
{
    "tools": {
        "bash": {
            "allowedCommands": [
                "zz:tree",
                "zz:prompt:read-only",
                "zz:gather:*",
                "zz:analyze:security-only",
                "zz:benchmark:safe-mode"
            ],
            "blockedCommands": [
                "zz:*:--unsafe",
                "zz:*:--execute",
                "zz:*:--modify"
            ]
        }
    },
    "security": {
        "logCommands": true,
        "requireConfirmation": ["write", "modify", "delete"],
        "maxConcurrentOperations": 3
    }
}
```

## Security Testing

### Comprehensive Security Test Suite

#### Input Validation Tests
```zig
test "input sanitization blocks shell injection" {
    const malicious_inputs = [_][]const u8{
        "*.zig; rm -rf /",
        "$(malicious)",
        "`command`",
        "../../../etc/passwd",
        "\x00\x01\x02",  // Null bytes and control chars
    };
    
    for (malicious_inputs) |input| {
        try std.testing.expectError(error.MaliciousInput, 
            validatePattern(input));
    }
}
```

#### Resource Limit Tests
```zig
test "resource limits prevent DoS attacks" {
    var mock_fs = MockFilesystem.init(allocator);
    defer mock_fs.deinit();
    
    // Create artificially large directory structure
    try createMassiveDirectoryStructure(&mock_fs, 100000);
    
    const config = Config{
        .max_files_processed = 1000,
        .max_execution_time_ms = 5000,
    };
    
    // Should terminate gracefully with resource limit error
    const result = tree.runWithConfig(&config, allocator, 
        mock_fs.interface(), &[_][:0]const u8{"."});
    try std.testing.expectError(error.ResourceLimitExceeded, result);
}
```

#### Path Traversal Tests
```zig
test "path traversal prevention" {
    const dangerous_paths = [_][]const u8{
        "../../../etc/passwd",
        "/proc/version",
        "~/../../root/.ssh",
        "..\\..\\windows\\system32",  // Windows-style (should be rejected)
        "symbolic_link_to_sensitive_file",
    };
    
    for (dangerous_paths) |path| {
        try std.testing.expectError(error.UnauthorizedPath, 
            validatePath(path));
    }
}
```

### Security Audit Process

#### Automated Security Scanning
```bash
# Static analysis for security issues
zig test src/test.zig --test-filter "security"

# Memory safety verification
zig build -Doptimize=Debug -Dsanitize-thread -Dsanitize-memory

# Fuzzing input validation
zig build fuzz-patterns --iterations=100000
```

#### Manual Security Review Checklist
- [ ] **Input validation:** All user inputs sanitized
- [ ] **Path handling:** No directory traversal vulnerabilities
- [ ] **Resource limits:** DoS prevention mechanisms in place
- [ ] **Error messages:** No sensitive information leaked
- [ ] **Configuration:** Secure defaults, validation present
- [ ] **Dependencies:** No external dependencies introduced
- [ ] **Memory safety:** Zig compiler guarantees upheld

## Incident Response

### Security Vulnerability Handling

#### Reporting Process
1. **Email:** security@zz-project.org (hypothetical)
2. **PGP encryption encouraged** for sensitive reports
3. **Response time:** <48 hours for acknowledgment
4. **Disclosure timeline:** 90 days coordinated disclosure

#### Severity Classification
- **Critical:** Remote code execution, privilege escalation
- **High:** Local code execution, data exfiltration
- **Medium:** Information disclosure, DoS attacks
- **Low:** Configuration weaknesses, minor information leaks

#### Response Procedures
1. **Immediate assessment** of vulnerability scope and impact
2. **Patch development** with security team review
3. **Testing** against exploit scenarios
4. **Coordinated disclosure** with security community
5. **Post-incident review** and security improvements

### Security Monitoring

#### Audit Logging
```zig
pub fn logSecurityEvent(event_type: SecurityEventType, details: []const u8) void {
    const timestamp = std.time.timestamp();
    const log_entry = SecurityLogEntry{
        .timestamp = timestamp,
        .event_type = event_type,
        .details = details,
        .process_id = std.os.getpid(),
    };
    
    // Write to secure audit log
    writeToAuditLog(log_entry) catch |err| {
        // Fail securely - log to stderr if audit log unavailable
        std.debug.print("SECURITY AUDIT LOG FAILURE: {}\n", .{err});
    };
}
```

#### Runtime Security Checks
```zig
pub fn performRuntimeSecurityCheck() !void {
    // Verify binary integrity
    try verifyBinaryChecksum();
    
    // Check for suspicious environment variables
    try validateEnvironment();
    
    // Verify working directory permissions
    try checkWorkingDirectoryPermissions();
    
    // Monitor resource usage
    try checkResourceUsage();
}
```

This security architecture ensures that `zz` can be safely used in AI-assisted development environments while maintaining high performance and usability. Every security measure is designed to be transparent to legitimate users while effectively blocking malicious activities.