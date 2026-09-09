package com.sanjose.inventory.exception;

// Thrown when a delete is blocked because other records (e.g. assets) still
// reference the target row via a NO ACTION/RESTRICT foreign key — lets callers
// surface a specific, actionable message instead of a raw SQL constraint error.
public class ResourceInUseException extends RuntimeException {
    public ResourceInUseException(String message) {
        super(message);
    }
}
