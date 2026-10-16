package com.sanjose.inventory.exception;

import lombok.Getter;

// A status change or request decision was sent without its emailed confirmation code. A code has
// just been emailed; the client asks for it and repeats the same request with the X-Action-Otp header.
@Getter
public class ActionOtpRequiredException extends RuntimeException {
    private final String maskedEmail;

    public ActionOtpRequiredException(String message, String maskedEmail) {
        super(message);
        this.maskedEmail = maskedEmail;
    }
}
