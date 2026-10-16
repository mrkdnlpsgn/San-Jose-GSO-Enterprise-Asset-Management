package com.sanjose.inventory.exception;

// The X-Action-Otp code was wrong, expired, or used up — the client keeps its code prompt open.
public class ActionOtpInvalidException extends RuntimeException {
    public ActionOtpInvalidException(String message) {
        super(message);
    }
}
