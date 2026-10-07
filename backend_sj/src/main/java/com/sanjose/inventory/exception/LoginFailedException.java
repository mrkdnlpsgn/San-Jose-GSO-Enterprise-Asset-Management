package com.sanjose.inventory.exception;

import lombok.Getter;
import org.springframework.security.authentication.BadCredentialsException;

// Wrong password for an existing account — carries how many tries are left before the lockout.
@Getter
public class LoginFailedException extends BadCredentialsException {
    private final int attemptsRemaining;

    public LoginFailedException(int attemptsRemaining) {
        super("Invalid credentials");
        this.attemptsRemaining = attemptsRemaining;
    }
}
