package com.sanjose.inventory.exception;

// 403 — the user is signed in but their role/office doesn't allow this action.
public class ForbiddenException extends RuntimeException {
    public ForbiddenException(String message) {
        super(message);
    }
}
