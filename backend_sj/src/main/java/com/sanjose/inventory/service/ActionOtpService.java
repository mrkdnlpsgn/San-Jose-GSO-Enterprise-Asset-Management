package com.sanjose.inventory.service;

import com.sanjose.inventory.exception.ActionOtpInvalidException;
import com.sanjose.inventory.exception.ActionOtpRequiredException;
import jakarta.servlet.http.HttpServletRequest;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Service;
import org.springframework.web.context.request.RequestContextHolder;
import org.springframework.web.context.request.ServletRequestAttributes;

// Emailed one-time code before a change to an asset's status (staff request or admin change) and
// before an admin approves or rejects a staff request. Two round trips of the same request:
//   1. no X-Action-Otp header -> a code is emailed, 428 ACTION_OTP_REQUIRED
//   2. the client repeats the request with the code -> checked, then the action goes ahead
// Call it from a controller (outside the services' transactions) before anything is changed,
// so the code saved in step 1 isn't rolled back by the 428.
//
// A server with email turned off can't deliver codes, so it skips this check (and says so in the
// log) rather than block every status change and approval.
@Slf4j
@Service
@RequiredArgsConstructor
public class ActionOtpService {

    public static final String HEADER = "X-Action-Otp";

    private final AuthService authService;
    private final EmailService emailService;

    // `action` completes "You are about to ..." in the email, e.g. "change the status of COA-2026-001".
    public void require(String action) {
        String username = SecurityContextHolder.getContext().getAuthentication().getName();
        if (!emailService.isEnabled()) {
            log.warn("Email is not configured (notifications.enabled / mail.from). No confirmation code asked for: {} by {}",
                action, username);
            return;
        }
        String code = currentRequest().getHeader(HEADER);
        if (code == null || code.isBlank()) {
            String email = authService.requestActionOtp(username, action);
            throw new ActionOtpRequiredException(
                "Enter the 6-digit code we emailed to " + email + " to " + action + ".", email);
        }
        try {
            authService.verifyDeleteOtp(username, code.trim());
        } catch (IllegalArgumentException e) {
            throw new ActionOtpInvalidException(e.getMessage());
        }
    }

    private static HttpServletRequest currentRequest() {
        return ((ServletRequestAttributes) RequestContextHolder.currentRequestAttributes()).getRequest();
    }
}
