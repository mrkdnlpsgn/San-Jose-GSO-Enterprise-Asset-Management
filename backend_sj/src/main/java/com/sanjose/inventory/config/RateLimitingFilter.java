package com.sanjose.inventory.config;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.Deque;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentLinkedDeque;

@Component
@Order(1)
public class RateLimitingFilter extends OncePerRequestFilter {

    // Tier 1 — global: 100 req / 60 s per IP (all endpoints)
    private static final int  GLOBAL_MAX  = 100;
    private static final long GLOBAL_WIN  = 60_000L;

    // Tier 2 — write ops (POST/PUT/DELETE, non-auth): 30 req / 60 s per IP
    private static final int  WRITE_MAX   = 30;
    private static final long WRITE_WIN   = 60_000L;

    // Tier 3 — auth login: 5 attempts / 15 min per IP  (stricter than before)
    private static final int  AUTH_MAX    = 5;
    private static final long AUTH_WIN    = 15 * 60_000L;

    private final Map<String, Deque<Long>> globalBucket = new ConcurrentHashMap<>();
    private final Map<String, Deque<Long>> writeBucket  = new ConcurrentHashMap<>();
    private final Map<String, Deque<Long>> authBucket   = new ConcurrentHashMap<>();

    // The SSE stream is a single long-lived connection per client; browser
    // auto-reconnects on drop could otherwise trip the global bucket.
    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        return request.getRequestURI().startsWith("/api/events/");
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain chain) throws ServletException, IOException {

        String ip     = getClientIp(request);
        String method = request.getMethod().toUpperCase();
        String uri    = request.getRequestURI();

        // Tier 1: global rate limit
        if (isExceeded(globalBucket, ip, GLOBAL_MAX, GLOBAL_WIN)) {
            reject(response, "Too many requests. Please slow down.", 60);
            return;
        }
        record(globalBucket, ip);

        // Tier 2: write-operation rate limit (non-auth endpoints)
        boolean isWrite = method.equals("POST") || method.equals("PUT") || method.equals("DELETE");
        if (isWrite && !uri.startsWith("/api/auth/")) {
            if (isExceeded(writeBucket, ip, WRITE_MAX, WRITE_WIN)) {
                reject(response, "Too many write requests. Please wait before retrying.", 60);
                return;
            }
            record(writeBucket, ip);
        }

        // Tier 3: login brute-force limit
        if (uri.equals("/api/auth/login") && method.equals("POST")) {
            if (isExceeded(authBucket, ip, AUTH_MAX, AUTH_WIN)) {
                reject(response, "Too many login attempts. Please wait 15 minutes and try again.", 900);
                return;
            }
            record(authBucket, ip);
        }

        chain.doFilter(request, response);
    }

    private boolean isExceeded(Map<String, Deque<Long>> bucket, String key, int max, long windowMs) {
        Deque<Long> ts = bucket.computeIfAbsent(key, k -> new ConcurrentLinkedDeque<>());
        long now = System.currentTimeMillis();
        ts.removeIf(t -> now - t > windowMs);
        return ts.size() >= max;
    }

    private void record(Map<String, Deque<Long>> bucket, String key) {
        bucket.computeIfAbsent(key, k -> new ConcurrentLinkedDeque<>()).addLast(System.currentTimeMillis());
    }

    private void reject(HttpServletResponse response, String message, int retryAfterSeconds)
            throws IOException {
        response.setStatus(429);
        response.setContentType("application/json");
        response.setHeader("Retry-After", String.valueOf(retryAfterSeconds));
        response.setHeader("X-RateLimit-Reset",
                String.valueOf(System.currentTimeMillis() / 1000 + retryAfterSeconds));
        response.getWriter().write(
                "{\"status\":429,\"message\":\"" + message + "\",\"retryAfter\":" + retryAfterSeconds + "}");
    }

    private String getClientIp(HttpServletRequest request) {
        String forwarded = request.getHeader("X-Forwarded-For");
        if (forwarded != null && !forwarded.isBlank()) {
            return forwarded.split(",")[0].trim();
        }
        return request.getRemoteAddr();
    }
}
