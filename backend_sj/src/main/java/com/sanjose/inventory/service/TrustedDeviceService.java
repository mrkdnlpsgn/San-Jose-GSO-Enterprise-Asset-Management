package com.sanjose.inventory.service;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Base64;
import java.util.List;
import java.util.Map;

// "Don't ask for a code on this computer for 30 days": after a successful 2-step sign-in the
// browser keeps a signed token (HttpOnly cookie, only sent to /api/auth), and later sign-ins on
// that browser skip the emailed code — the password is still required.
//
// Token = "<userId>.<tokenVersion>.<expiresEpochSeconds>.<HMAC>". No table: it is checked
// against the account's current token_version, which already goes up on a password change or
// reset, deactivation, and "Forget remembered devices" — any of those invalidates every
// remembered device at once. One cookie holds tokens for up to MAX_PER_BROWSER accounts (shared
// office PCs), separated by '|'.
@Service
public class TrustedDeviceService {

    public static final String COOKIE = "trusted_devices";
    public static final Duration LIFETIME = Duration.ofDays(30);
    private static final int MAX_PER_BROWSER = 10;

    private final JdbcTemplate jdbcTemplate;
    private final byte[] key;

    public TrustedDeviceService(JdbcTemplate jdbcTemplate, @Value("${jwt.secret}") String secret) {
        this.jdbcTemplate = jdbcTemplate;
        this.key = ("trusted-device:" + secret).getBytes(StandardCharsets.UTF_8);
    }

    // Is this account remembered on the browser that sent cookieValue?
    public boolean isTrusted(long userId, int tokenVersion, String cookieValue) {
        long now = Instant.now().getEpochSecond();
        for (String token : split(cookieValue)) {
            long[] t = parse(token);
            if (t != null && t[0] == userId && t[1] == tokenVersion && t[2] > now) return true;
        }
        return false;
    }

    // The new cookie value after remembering `username` on this browser: its old token (and any
    // expired or unreadable ones) dropped, the new one added, oldest trimmed past the cap.
    public String remember(String username, String cookieValue) {
        Map<String, Object> u = jdbcTemplate.queryForMap(
            "SELECT user_id, token_version FROM users WHERE LOWER(username) = LOWER(?)", username);
        long userId = ((Number) u.get("user_id")).longValue();
        int tokenVersion = ((Number) u.get("token_version")).intValue();
        long now = Instant.now().getEpochSecond();

        List<String> kept = new ArrayList<>();
        for (String token : split(cookieValue)) {
            long[] t = parse(token);
            if (t != null && t[0] != userId && t[2] > now) kept.add(token);
        }
        kept.add(sign(userId + "." + tokenVersion + "." + (now + LIFETIME.toSeconds())));
        while (kept.size() > MAX_PER_BROWSER) kept.remove(0);
        return String.join("|", kept);
    }

    private static List<String> split(String cookieValue) {
        if (cookieValue == null || cookieValue.isBlank()) return List.of();
        return List.of(cookieValue.split("\\|"));
    }

    // [userId, tokenVersion, expires] when the signature checks out, else null.
    private long[] parse(String token) {
        int cut = token.lastIndexOf('.');
        if (cut <= 0) return null;
        String payload = token.substring(0, cut);
        byte[] expected = sign(payload).getBytes(StandardCharsets.UTF_8);
        byte[] given = token.getBytes(StandardCharsets.UTF_8);
        if (!MessageDigest.isEqual(expected, given)) return null;
        String[] p = payload.split("\\.");
        if (p.length != 3) return null;
        try {
            return new long[]{ Long.parseLong(p[0]), Long.parseLong(p[1]), Long.parseLong(p[2]) };
        } catch (NumberFormatException e) {
            return null;
        }
    }

    // "<payload>.<base64url HMAC-SHA256 of payload>"
    private String sign(String payload) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(key, "HmacSHA256"));
            byte[] sig = mac.doFinal(payload.getBytes(StandardCharsets.UTF_8));
            return payload + "." + Base64.getUrlEncoder().withoutPadding().encodeToString(sig);
        } catch (Exception e) {
            throw new IllegalStateException("Could not sign the device token", e);
        }
    }
}
