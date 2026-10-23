package com.sanjose.inventory.config;

import com.sanjose.inventory.service.IdempotencyService;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.MediaType;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;
import org.springframework.web.util.ContentCachingResponseWrapper;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.Optional;

// Guards create endpoints against duplicate submission (double-tap, client retry after
// a dropped response) - purely opt-in via the client-supplied Idempotency-Key header,
// so requests without it (and non-POST requests) are entirely unaffected.
@Slf4j
@Component
@RequiredArgsConstructor
public class IdempotencyFilter extends OncePerRequestFilter {

    private static final String HEADER = "Idempotency-Key";

    private final IdempotencyService idempotencyService;

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {

        String key = request.getHeader(HEADER);
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();

        if (!"POST".equalsIgnoreCase(request.getMethod()) || key == null || key.isBlank()
                || auth == null || !auth.isAuthenticated()) {
            chain.doFilter(request, response);
            return;
        }

        String method = request.getMethod();
        String path = request.getRequestURI();
        String username = auth.getName();

        Optional<IdempotencyService.CachedResponse> cached =
            idempotencyService.findCompleted(key, method, path, username);
        if (cached.isPresent()) {
            log.info("Replaying cached response for Idempotency-Key {} on {} {}", key, method, path);
            response.setStatus(cached.get().status());
            response.setContentType(MediaType.APPLICATION_JSON_VALUE);
            response.getWriter().write(cached.get().body());
            return;
        }

        if (!idempotencyService.tryClaim(key, method, path, username)) {
            response.setStatus(HttpServletResponse.SC_CONFLICT);
            response.setContentType(MediaType.APPLICATION_JSON_VALUE);
            response.getWriter().write(
                "{\"message\":\"A request with this Idempotency-Key is already being processed.\"}");
            return;
        }

        ContentCachingResponseWrapper wrapped = new ContentCachingResponseWrapper(response);
        try {
            chain.doFilter(request, wrapped);
        } finally {
            String body = new String(wrapped.getContentAsByteArray(), StandardCharsets.UTF_8);
            idempotencyService.complete(key, method, path, username, wrapped.getStatus(), body);
            wrapped.copyBodyToResponse();
        }
    }
}
