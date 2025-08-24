/// JSON Linter Rules - Organized Validation Rules
///
/// Re-exports all validation rule functions for backward compatibility

// Import all rule modules
pub const strings = @import("strings.zig");
pub const numbers = @import("numbers.zig");
pub const objects = @import("objects.zig");
pub const arrays = @import("arrays.zig");

// Re-export main validation functions for backward compatibility
pub const validateString = strings.validateString;
pub const validateNumber = numbers.validateNumber;
pub const validateObject = objects.validateObject;
pub const validateArray = arrays.validateArray;

// Re-export utility functions
pub const skipToMatchingBrace = objects.skipToMatchingBrace;
