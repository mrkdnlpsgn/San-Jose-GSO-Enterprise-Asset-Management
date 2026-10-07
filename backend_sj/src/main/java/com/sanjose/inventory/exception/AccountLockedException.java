package com.sanjose.inventory.exception;

import lombok.Getter;
import org.springframework.security.authentication.LockedException;

// Too many wrong passwords — carries the seconds until the account unlocks, so the login
// screen can count down instead of guessing.
@Getter
public class AccountLockedException extends LockedException {
    private final long retryAfterSeconds;

    public AccountLockedException(String message, long retryAfterSeconds) {
        super(message);
        this.retryAfterSeconds = retryAfterSeconds;
    }
}
