package com.sanjose.inventory.service;

import com.sanjose.inventory.config.JwtUtil;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.security.authentication.LockedException;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;

import java.security.SecureRandom;
import java.sql.Timestamp;
import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

@Slf4j
@Service
@RequiredArgsConstructor
public class AuthService {

    @Value("${auth.max-failed-attempts:3}")
    private int maxFailedAttempts;

    @Value("${auth.lockout-minutes:15}")
    private int lockoutMinutes;

    @Value("${auth.forgot-password-cooldown-minutes:15}")
    private int forgotPasswordCooldownMinutes;

    @Value("${auth.forgot-password-otp-expiry-minutes:10}")
    private int otpExpiryMinutes;

    @Value("${auth.forgot-password-otp-max-attempts:5}")
    private int otpMaxAttempts;

    @Value("${auth.forgot-password-otp-resend-cooldown-seconds:60}")
    private int otpResendCooldownSeconds;

    @Value("${auth.login-otp-expiry-minutes:10}")
    private int loginOtpExpiryMinutes;

    @Value("${auth.login-otp-max-attempts:5}")
    private int loginOtpMaxAttempts;

    @Value("${auth.login-otp-resend-cooldown-seconds:60}")
    private int loginOtpResendCooldownSeconds;

    private static final SecureRandom OTP_RANDOM = new SecureRandom();

    private final JdbcTemplate jdbcTemplate;
    private final PasswordEncoder passwordEncoder;
    private final JwtUtil jwtUtil;
    private final EmailService emailService;
    private final AuditLogService auditLogService;
    private final PlatformTransactionManager transactionManager;

    // A failed-attempt counter (login lockout, OTP attempts) must survive even
    // though the caller immediately throws right after recording it — under the
    // enclosing @Transactional method, Spring's default rollback-on-RuntimeException
    // would otherwise silently undo the increment along with everything else,
    // defeating the attempt limit entirely (confirmed happening in practice before
    // this fix: failed_login_attempts and both *_otp_attempts columns stayed at 0
    // no matter how many wrong passwords/codes were submitted — lockout and OTP
    // brute-force limits never actually engaged). Running it in its own
    // REQUIRES_NEW transaction makes it durable regardless of what the caller
    // does next.
    private void recordAttemptDurably(Runnable jdbcCall) {
        TransactionTemplate tt = new TransactionTemplate(transactionManager);
        tt.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
        tt.executeWithoutResult(status -> jdbcCall.run());
    }

    private record LoginUserData(
        Long id, String username, String password, String fullName, String role,
        Boolean isActive, Integer failedLoginAttempts, LocalDateTime accountLockedUntil,
        Integer tokenVersion, Boolean mustChangePassword, LocalDateTime privacyAcknowledgedAt,
        Boolean twoFactorEnabled
    ) {}

    private record LoginOtpData(
        Long id, String username, String fullName, String role, Boolean isActive,
        Integer tokenVersion, LocalDateTime privacyAcknowledgedAt,
        String otpHash, LocalDateTime otpExpiresAt, Integer otpAttempts
    ) {}

    private record ForgotPasswordUserData(
        Long id, String username, String email, Boolean isActive,
        LocalDateTime lastPasswordResetAt, LocalDateTime otpExpiresAt
    ) {}

    private record PasswordResetOtpData(
        Long id, Boolean isActive, String otpHash, LocalDateTime otpExpiresAt, Integer otpAttempts
    ) {}

    @Transactional
    public Map<String, Object> login(String identifier, String password) {
        if (identifier == null || identifier.isBlank())
            throw new BadCredentialsException("Invalid credentials");

        LoginUserData user = lookupForLogin(identifier);
        if (user == null) throw new BadCredentialsException("Invalid credentials");

        if (!Boolean.TRUE.equals(user.isActive()))
            throw new LockedException("Account is deactivated");

        if (user.accountLockedUntil() != null && LocalDateTime.now().isBefore(user.accountLockedUntil()))
            throw new LockedException("Account is temporarily locked. Try again after " + lockoutMinutes + " minutes.");

        if (!passwordEncoder.matches(password, user.password())) {
            recordAttemptDurably(() -> jdbcTemplate.update("CALL sp_auth_login_failure(?, ?, ?)",
                user.id(), maxFailedAttempts, lockoutMinutes));
            throw new BadCredentialsException("Invalid credentials");
        }

        jdbcTemplate.update("CALL sp_auth_login_success(?)", user.id());

        // Correct credentials, but this is a temp password (fresh account or admin
        // reset) — withhold the session token until the user picks their own password.
        // Takes priority over 2FA: finish the forced change first, then 2FA applies
        // on the next real login.
        if (Boolean.TRUE.equals(user.mustChangePassword())) {
            return Map.of("mustChangePassword", true, "username", user.username());
        }

        // Correct credentials, 2FA enabled on this account (everyone except admin
        // and ict_staff, who are trusted fixture/service accounts) — withhold the
        // session token until the emailed code is verified via verifyLoginOtp().
        if (Boolean.TRUE.equals(user.twoFactorEnabled())) {
            issueOrReuseLoginOtp(user);
            return Map.of("requiresTwoFactor", true, "username", user.username());
        }

        String token = jwtUtil.generateToken(user.username(), user.tokenVersion() != null ? user.tokenVersion() : 0);

        Map<String, Object> userMap = new HashMap<>();
        userMap.put("id", user.id());
        userMap.put("username", user.username());
        userMap.put("fullName", user.fullName());
        userMap.put("role", user.role());
        userMap.put("privacyAcknowledgedAt", user.privacyAcknowledgedAt());

        return Map.of("token", token, "user", userMap);
    }

    // Shared by login()'s first hit and any resubmission before the code is verified —
    // avoids re-emailing a fresh code (and restarting the attempt counter) if the user
    // just resubmits the login form within the cooldown window.
    private void issueOrReuseLoginOtp(LoginUserData user) {
        List<LoginOtpData> rows = jdbcTemplate.query(
            "CALL sp_auth_get_login_otp(?)", LOGIN_OTP_MAPPER, user.username());
        LoginOtpData existing = rows.isEmpty() ? null : rows.get(0);

        if (existing != null && existing.otpExpiresAt() != null) {
            LocalDateTime issuedAt = existing.otpExpiresAt().minusMinutes(loginOtpExpiryMinutes);
            if (LocalDateTime.now().isBefore(issuedAt.plusSeconds(loginOtpResendCooldownSeconds))) return;
        }

        // No email on file: nothing to send. Fails closed — the account stays
        // permanently unable to complete login rather than silently skipping 2FA.
        List<ForgotPasswordUserData> emailRows = jdbcTemplate.query(
            "CALL sp_auth_get_user_for_forgot_password_request(?)",
            (rs, rn) -> new ForgotPasswordUserData(
                rs.getLong("id"), rs.getString("username"), rs.getString("email"),
                rs.getObject("isActive", Boolean.class), null, null),
            user.username());
        if (emailRows.isEmpty() || emailRows.get(0).email() == null || emailRows.get(0).email().isBlank()) {
            log.warn("2FA enabled for {} but no email on file — login cannot complete.", user.username());
            return;
        }

        String otp = String.format("%06d", OTP_RANDOM.nextInt(1_000_000));
        LocalDateTime expiresAt = LocalDateTime.now().plusMinutes(loginOtpExpiryMinutes);
        jdbcTemplate.update("CALL sp_auth_set_login_otp(?, ?, ?)",
            user.id(), passwordEncoder.encode(otp), Timestamp.valueOf(expiresAt));

        String html = "<p>Your San Jose GSO Enterprise Asset Management login verification code is:</p>"
            + "<p style=\"font-size:28px;font-weight:bold;letter-spacing:6px;\">" + otp + "</p>"
            + "<p>This code expires in " + loginOtpExpiryMinutes + " minutes. "
            + "If you didn't just try to log in, you can safely ignore this email.</p>";
        emailService.send(emailRows.get(0).email(), "Your login verification code", html);
    }

    private static final org.springframework.jdbc.core.RowMapper<LoginOtpData> LOGIN_OTP_MAPPER = (rs, rn) -> {
        Timestamp expTs = rs.getTimestamp("otpExpiresAt");
        Timestamp privacyTs = rs.getTimestamp("privacyAcknowledgedAt");
        return new LoginOtpData(
            rs.getLong("id"),
            rs.getString("username"),
            rs.getString("fullName"),
            rs.getString("role"),
            rs.getObject("isActive", Boolean.class),
            rs.getObject("tokenVersion", Integer.class),
            privacyTs != null ? privacyTs.toLocalDateTime() : null,
            rs.getString("otpHash"),
            expTs != null ? expTs.toLocalDateTime() : null,
            rs.getObject("otpAttempts", Integer.class)
        );
    };

    // Step 2 of login 2FA: verify the emailed code and issue the same session a
    // normal password-only login would have.
    @Transactional
    public Map<String, Object> verifyLoginOtp(String identifier, String otp) {
        if (identifier == null || identifier.isBlank())
            throw new BadCredentialsException("Invalid credentials");

        List<LoginOtpData> rows = jdbcTemplate.query("CALL sp_auth_get_login_otp(?)", LOGIN_OTP_MAPPER, identifier);

        // Every failure path throws the identical message — unknown username, no
        // pending code, expired code, wrong code, and too-many-attempts are all
        // indistinguishable to the caller (mirrors confirmPasswordReset).
        if (rows.isEmpty()) throw new IllegalArgumentException("Invalid or expired code.");
        LoginOtpData data = rows.get(0);

        boolean eligible = Boolean.TRUE.equals(data.isActive())
            && data.otpHash() != null
            && data.otpExpiresAt() != null
            && LocalDateTime.now().isBefore(data.otpExpiresAt())
            && (data.otpAttempts() == null || data.otpAttempts() < loginOtpMaxAttempts);

        if (!eligible) throw new IllegalArgumentException("Invalid or expired code.");

        if (!passwordEncoder.matches(otp, data.otpHash())) {
            recordAttemptDurably(() -> jdbcTemplate.update(
                "CALL sp_auth_increment_login_otp_attempts(?)", data.id()));
            throw new IllegalArgumentException("Invalid or expired code.");
        }

        jdbcTemplate.update("CALL sp_auth_clear_login_otp(?)", data.id());

        String token = jwtUtil.generateToken(data.username(), data.tokenVersion() != null ? data.tokenVersion() : 0);

        Map<String, Object> userMap = new HashMap<>();
        userMap.put("id", data.id());
        userMap.put("username", data.username());
        userMap.put("fullName", data.fullName());
        userMap.put("role", data.role());
        userMap.put("privacyAcknowledgedAt", data.privacyAcknowledgedAt());

        return Map.of("token", token, "user", userMap);
    }

    // Step 2 of the forced-password-change flow: re-proves the temp password, then
    // swaps it and issues the same session a normal login would have.
    @Transactional
    public Map<String, Object> forceChangePassword(String identifier, String currentPassword, String newPassword) {
        LoginUserData user = lookupForLogin(identifier);
        if (user == null) throw new BadCredentialsException("Invalid credentials");

        if (!Boolean.TRUE.equals(user.isActive()))
            throw new LockedException("Account is deactivated");

        if (user.accountLockedUntil() != null && LocalDateTime.now().isBefore(user.accountLockedUntil()))
            throw new LockedException("Account is temporarily locked. Try again after " + lockoutMinutes + " minutes.");

        if (!Boolean.TRUE.equals(user.mustChangePassword()))
            throw new IllegalStateException("This account does not require a password change.");

        if (!passwordEncoder.matches(currentPassword, user.password())) {
            recordAttemptDurably(() -> jdbcTemplate.update("CALL sp_auth_login_failure(?, ?, ?)",
                user.id(), maxFailedAttempts, lockoutMinutes));
            throw new BadCredentialsException("Invalid credentials");
        }

        jdbcTemplate.update("CALL sp_auth_complete_forced_password_change(?, ?)",
            user.id(), passwordEncoder.encode(newPassword));
        auditLogService.log("USER_PASSWORD_CHANGED", "Users", user.id(), "user",
            "Password changed to complete mandatory first login: " + user.username());

        // token_version was just bumped by the proc above — the value on `user` predates
        // that, so start from it and add the +1 the proc applied rather than re-querying.
        int newTokenVersion = (user.tokenVersion() != null ? user.tokenVersion() : 0) + 1;
        String token = jwtUtil.generateToken(user.username(), newTokenVersion);

        Map<String, Object> userMap = new HashMap<>();
        userMap.put("id", user.id());
        userMap.put("username", user.username());
        userMap.put("fullName", user.fullName());
        userMap.put("role", user.role());
        userMap.put("privacyAcknowledgedAt", user.privacyAcknowledgedAt());

        return Map.of("token", token, "user", userMap);
    }

    // Backs GET /api/auth/me — same user-map shape as login()/forceChangePassword()
    // (in particular, privacyAcknowledgedAt) so a client rehydrating its session
    // from an existing cookie sees the same fields it would have gotten at login.
    public Map<String, Object> getCurrentUserMap(String username) {
        LoginUserData user = lookupForLogin(username);
        if (user == null) return null;

        Map<String, Object> userMap = new HashMap<>();
        userMap.put("id", user.id());
        userMap.put("username", user.username());
        userMap.put("fullName", user.fullName());
        userMap.put("role", user.role());
        userMap.put("privacyAcknowledgedAt", user.privacyAcknowledgedAt());
        return userMap;
    }

    private LoginUserData lookupForLogin(String identifier) {
        List<LoginUserData> rows = jdbcTemplate.query(
            "CALL sp_auth_get_user_for_login(?)",
            (rs, rn) -> {
                Timestamp lockTs = rs.getTimestamp("accountLockedUntil");
                Timestamp privacyTs = rs.getTimestamp("privacyAcknowledgedAt");
                return new LoginUserData(
                    rs.getLong("id"),
                    rs.getString("username"),
                    rs.getString("password"),
                    rs.getString("fullName"),
                    rs.getString("role"),
                    rs.getObject("isActive", Boolean.class),
                    rs.getObject("failedLoginAttempts", Integer.class),
                    lockTs != null ? lockTs.toLocalDateTime() : null,
                    rs.getObject("tokenVersion", Integer.class),
                    rs.getObject("mustChangePassword", Boolean.class),
                    privacyTs != null ? privacyTs.toLocalDateTime() : null,
                    rs.getObject("twoFactorEnabled", Boolean.class)
                );
            },
            identifier);
        return rows.isEmpty() ? null : rows.get(0);
    }

    // Step 1: email a one-time code to the account's registered address. Requiring
    // possession of the inbox (not just the username) is what prevents anyone who
    // merely knows/guesses a username from taking over the account outright.
    @Transactional
    public void requestPasswordReset(String username) {
        List<ForgotPasswordUserData> rows = jdbcTemplate.query(
            "CALL sp_auth_get_user_for_forgot_password_request(?)",
            (rs, rn) -> {
                Timestamp lastResetTs = rs.getTimestamp("lastPasswordResetAt");
                Timestamp otpExpTs = rs.getTimestamp("otpExpiresAt");
                return new ForgotPasswordUserData(
                    rs.getLong("id"),
                    rs.getString("username"),
                    rs.getString("email"),
                    rs.getObject("isActive", Boolean.class),
                    lastResetTs != null ? lastResetTs.toLocalDateTime() : null,
                    otpExpTs != null ? otpExpTs.toLocalDateTime() : null
                );
            },
            username);

        // Unknown username, inactive account, no email on file, or still in cooldown:
        // no-op rather than reveal anything via a distinguishable response — the
        // controller returns the same generic message in every case.
        if (rows.isEmpty()) return;
        ForgotPasswordUserData user = rows.get(0);
        if (!Boolean.TRUE.equals(user.isActive())) return;
        if (user.email() == null || user.email().isBlank()) return;

        if (user.lastPasswordResetAt() != null) {
            LocalDateTime nextAllowed = user.lastPasswordResetAt().plusMinutes(forgotPasswordCooldownMinutes);
            if (LocalDateTime.now().isBefore(nextAllowed)) return;
        }

        // Don't spam a fresh code/email if one was just requested — a pending OTP's
        // issued-at time is derivable from its expiry (expiry = issuedAt + otpExpiryMinutes).
        if (user.otpExpiresAt() != null) {
            LocalDateTime issuedAt = user.otpExpiresAt().minusMinutes(otpExpiryMinutes);
            if (LocalDateTime.now().isBefore(issuedAt.plusSeconds(otpResendCooldownSeconds))) return;
        }

        String otp = String.format("%06d", OTP_RANDOM.nextInt(1_000_000));
        LocalDateTime expiresAt = LocalDateTime.now().plusMinutes(otpExpiryMinutes);
        jdbcTemplate.update("CALL sp_auth_set_password_reset_otp(?, ?, ?)",
            user.id(), passwordEncoder.encode(otp), Timestamp.valueOf(expiresAt));

        String html = "<p>Your San Jose GSO Enterprise Asset Management password reset code is:</p>"
            + "<p style=\"font-size:28px;font-weight:bold;letter-spacing:6px;\">" + otp + "</p>"
            + "<p>This code expires in " + otpExpiryMinutes + " minutes. "
            + "If you didn't request this, you can safely ignore this email.</p>";
        emailService.send(user.email(), "Your password reset code", html);
    }

    // Step 2: verify the emailed code and set the new password in one call.
    @Transactional
    public void confirmPasswordReset(String username, String otp, String newPassword) {
        List<PasswordResetOtpData> rows = jdbcTemplate.query(
            "CALL sp_auth_get_password_reset_otp(?)",
            (rs, rn) -> {
                Timestamp expTs = rs.getTimestamp("otpExpiresAt");
                return new PasswordResetOtpData(
                    rs.getLong("id"),
                    rs.getObject("isActive", Boolean.class),
                    rs.getString("otpHash"),
                    expTs != null ? expTs.toLocalDateTime() : null,
                    rs.getObject("otpAttempts", Integer.class)
                );
            },
            username);

        // Every failure path below throws the exact same message — unknown username,
        // no pending code, expired code, wrong code, and too-many-attempts are all
        // indistinguishable to the caller.
        if (rows.isEmpty()) throw new IllegalArgumentException("Invalid or expired code.");
        PasswordResetOtpData data = rows.get(0);

        boolean eligible = Boolean.TRUE.equals(data.isActive())
            && data.otpHash() != null
            && data.otpExpiresAt() != null
            && LocalDateTime.now().isBefore(data.otpExpiresAt())
            && (data.otpAttempts() == null || data.otpAttempts() < otpMaxAttempts);

        if (!eligible) throw new IllegalArgumentException("Invalid or expired code.");

        if (!passwordEncoder.matches(otp, data.otpHash())) {
            recordAttemptDurably(() -> jdbcTemplate.update(
                "CALL sp_auth_increment_password_reset_otp_attempts(?)", data.id()));
            throw new IllegalArgumentException("Invalid or expired code.");
        }

        jdbcTemplate.update("CALL sp_auth_forgot_password_reset(?, ?)",
            data.id(), passwordEncoder.encode(newPassword));

        auditLogService.log("USER_PASSWORD_RESET", "Users", data.id(), "user",
            "Password reset via forgot-password flow: " + username);
    }

    // Records that the currently-authenticated user has read the Data Privacy Notice.
    // Identity comes from the JWT-backed SecurityContext, not a request body — no
    // separate credential check needed since the caller already holds a valid session.
    @Transactional
    public LocalDateTime acknowledgePrivacy(String username) {
        LoginUserData user = lookupForLogin(username);
        if (user == null) throw new BadCredentialsException("Invalid credentials");

        jdbcTemplate.update("CALL sp_auth_acknowledge_privacy(?)", user.id());
        return LocalDateTime.now();
    }
}
