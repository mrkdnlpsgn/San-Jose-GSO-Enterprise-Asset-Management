package com.sanjose.inventory.config;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ReadListener;
import jakarta.servlet.ServletException;
import jakarta.servlet.ServletInputStream;
import jakarta.servlet.http.Cookie;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletRequestWrapper;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.security.InvalidKeyException;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;

/**
 * Validates inbound webhook requests to /api/scanner/** using HMAC-SHA256.
 *
 * Required request headers:
 *   X-Webhook-Signature-256  - "sha256=<hex(HMAC-SHA256(timestamp.body, secret))>"
 *   X-Webhook-Timestamp      - Unix epoch seconds (request is rejected if > 5 min old)
 *   X-Webhook-Id             - Unique ID per delivery (for idempotency / log correlation)
 *
 * Set webhook.verification.enabled=false in application.properties to skip
 * signature checks during local development / Postman testing.
 */
@Component
@Order(2)
public class WebhookVerificationFilter extends OncePerRequestFilter {

    private static final long   MAX_AGE_MS      = 5 * 60_000L; // 5-minute replay window
    private static final String HMAC_ALGO       = "HmacSHA256";
    private static final String SIG_HEADER      = "X-Webhook-Signature-256";
    private static final String TS_HEADER       = "X-Webhook-Timestamp";
    private static final String ID_HEADER       = "X-Webhook-Id";

    @Value("${webhook.secret:}")
    private String webhookSecret;

    @Value("${webhook.verification.enabled:true}")
    private boolean verificationEnabled;

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        return !request.getRequestURI().startsWith("/api/scanner/");
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain chain) throws ServletException, IOException {

        if (!verificationEnabled) {
            chain.doFilter(request, response);
            return;
        }

        // Authenticated frontend users (JWT cookie) bypass webhook HMAC - hardware devices must sign
        if (hasJwtCookie(request)) {
            chain.doFilter(request, response);
            return;
        }

        String signature  = request.getHeader(SIG_HEADER);
        String timestamp  = request.getHeader(TS_HEADER);
        String webhookId  = request.getHeader(ID_HEADER);

        if (signature == null || timestamp == null || webhookId == null) {
            sendError(response, 401,
                "Missing required webhook headers: " + SIG_HEADER + ", " + TS_HEADER + ", " + ID_HEADER);
            return;
        }

        // Replay-attack prevention - reject requests with a timestamp outside the 5-min window
        try {
            long requestEpochMs = Long.parseLong(timestamp) * 1000L;
            if (Math.abs(System.currentTimeMillis() - requestEpochMs) > MAX_AGE_MS) {
                sendError(response, 401,
                    "Webhook timestamp is outside the acceptable 5-minute window. Possible replay attack.");
                return;
            }
        } catch (NumberFormatException e) {
            sendError(response, 400, TS_HEADER + " must be a Unix epoch integer (seconds).");
            return;
        }

        // Read body eagerly so we can verify the signature before the controller sees it
        byte[] rawBody = request.getInputStream().readAllBytes();

        // Signing payload: timestamp + "." + body  (same convention as Stripe / GitHub)
        String signingPayload = timestamp + "." + new String(rawBody, StandardCharsets.UTF_8);

        try {
            String expected = "sha256=" + hmacSHA256Hex(signingPayload, webhookSecret);
            if (!constantTimeEquals(expected, signature)) {
                sendError(response, 401, "Invalid webhook signature.");
                return;
            }
        } catch (NoSuchAlgorithmException | InvalidKeyException e) {
            sendError(response, 500, "Webhook signature verification error.");
            return;
        }

        // Re-wrap the request so the controller can still read the body
        chain.doFilter(new CachedBodyRequestWrapper(request, rawBody), response);
    }

    private String hmacSHA256Hex(String data, String key)
            throws NoSuchAlgorithmException, InvalidKeyException {
        Mac mac = Mac.getInstance(HMAC_ALGO);
        mac.init(new SecretKeySpec(key.getBytes(StandardCharsets.UTF_8), HMAC_ALGO));
        return HexFormat.of().formatHex(mac.doFinal(data.getBytes(StandardCharsets.UTF_8)));
    }

    /** Constant-time comparison to prevent timing attacks. */
    private boolean constantTimeEquals(String a, String b) {
        if (a.length() != b.length()) return false;
        int diff = 0;
        for (int i = 0; i < a.length(); i++) {
            diff |= a.charAt(i) ^ b.charAt(i);
        }
        return diff == 0;
    }

    private boolean hasJwtCookie(HttpServletRequest request) {
        Cookie[] cookies = request.getCookies();
        if (cookies == null) return false;
        for (Cookie cookie : cookies) {
            if ("jwt".equals(cookie.getName()) && !cookie.getValue().isBlank()) return true;
        }
        return false;
    }

    private void sendError(HttpServletResponse response, int status, String message)
            throws IOException {
        response.setStatus(status);
        response.setContentType("application/json");
        response.getWriter().write(
            "{\"status\":" + status + ",\"message\":\"" + message.replace("\"", "\\\"") + "\"}");
    }

    /** Wraps a consumed input stream so downstream filters/controllers can re-read the body. */
    private static class CachedBodyRequestWrapper extends HttpServletRequestWrapper {

        private final byte[] cachedBody;

        CachedBodyRequestWrapper(HttpServletRequest request, byte[] cachedBody) {
            super(request);
            this.cachedBody = cachedBody;
        }

        @Override
        public ServletInputStream getInputStream() {
            ByteArrayInputStream bais = new ByteArrayInputStream(cachedBody);
            return new ServletInputStream() {
                @Override public int     read()                              { return bais.read(); }
                @Override public boolean isFinished()                       { return bais.available() == 0; }
                @Override public boolean isReady()                          { return true; }
                @Override public void    setReadListener(ReadListener rl)   { throw new UnsupportedOperationException(); }
            };
        }
    }
}
