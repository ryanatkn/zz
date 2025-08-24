/// ZON Linter Rules - Organized Validation Rules
///
/// Re-exports all validation rule functions for backward compatibility

// Import all rule modules
pub const strings = @import("strings.zig");
pub const numbers = @import("numbers.zig");
pub const objects = @import("objects.zig");
pub const arrays = @import("arrays.zig");
pub const schema = @import("schema.zig");

// Re-export main validation functions for backward compatibility
pub const validateString = strings.validateString;
pub const validateField = strings.validateField;
pub const validateEnumLiteral = strings.validateEnumLiteral;
pub const validateIdentifierText = strings.validateIdentifierText;

pub const validateNumber = numbers.validateNumber;

pub const validateObject = objects.validateObject;
pub const skipToMatchingBrace = objects.skipToMatchingBrace;

pub const validateArray = arrays.validateArray;

pub const detectSchemaType = schema.detectSchemaType;
pub const validateBuildField = schema.validateBuildField;
pub const SchemaType = schema.SchemaType;
