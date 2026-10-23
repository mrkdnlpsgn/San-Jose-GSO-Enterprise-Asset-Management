package com.sanjose.inventory.config;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.Cookie;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.web.authentication.WebAuthenticationDetailsSource;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;
import java.io.IOException;
import java.util.Set;

@Slf4j
@Component
public class JwtAuthFilter extends OncePerRequestFilter {

    private final JwtUtil jwtUtil;
    private final UserDetailsService userDetailsService;

    @Value("${cookie.secure:false}")
    private boolean cookieSecure;

    // Signed-out actions. A leftover session cookie must not block them: after a password
    // change the old cookie is stale, and rejecting it here kept the new password from ever
    // being checked (the login page then showed "account deactivated").
    private static final Set<String> SIGNED_OUT_PATHS = Set.of(
        "/api/auth/login", "/api/auth/login/verify-otp", "/api/auth/force-change-password",
        "/api/auth/logout", "/api/auth/forgot-password/request", "/api/auth/forgot-password/confirm");

    public JwtAuthFilter(JwtUtil jwtUtil, UserDetailsService userDetailsService) {
        this.jwtUtil = jwtUtil;
        this.userDetailsService = userDetailsService;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain chain) throws ServletException, IOException {
        String token = null;
        Cookie[] cookies = request.getCookies();
        if (cookies != null) {
            for (Cookie cookie : cookies) {
                if ("jwt".equals(cookie.getName())) {
                    token = cookie.getValue();
                    break;
                }
            }
        }

        if (token == null) {
            chain.doFilter(request, response);
            return;
        }

        if (!jwtUtil.isValid(token)) {
            log.warn("Invalid or expired JWT from IP {} on {}", request.getRemoteAddr(), request.getRequestURI());
            rejectToken(request, response, chain, "Invalid or expired token.");
            return;
        }

        String email = jwtUtil.extractEmail(token);
        if (email != null) {
            UserDetails userDetails = userDetailsService.loadUserByUsername(email);

            // Reject tokens issued before the account's most recent password change -
            // otherwise a stolen session would outlive the very reset meant to kill it.
            if (userDetails instanceof AppUserDetails appUserDetails && appUserDetails.getTokenVersion() != null
                    && !appUserDetails.getTokenVersion().equals(jwtUtil.extractTokenVersion(token))) {
                log.warn("Stale JWT (token version mismatch) for {} on {}", email, request.getRequestURI());
                rejectToken(request, response, chain, "Your session has ended (your password was changed or the account was deactivated). Please sign in again.");
                return;
            }

            if (SecurityContextHolder.getContext().getAuthentication() == null) {
                UsernamePasswordAuthenticationToken auth = new UsernamePasswordAuthenticationToken(
                        userDetails, null, userDetails.getAuthorities());
                auth.setDetails(new WebAuthenticationDetailsSource().buildDetails(request));
                SecurityContextHolder.getContext().setAuthentication(auth);
            }
        }

        chain.doFilter(request, response);
    }

    // A bad or stale session cookie: tell the browser to drop it, then let signed-out
    // actions carry on without a session; anything else gets a 401.
    private void rejectToken(HttpServletRequest request, HttpServletResponse response, FilterChain chain,
                             String message) throws IOException, ServletException {
        Cookie clear = new Cookie("jwt", "");
        clear.setHttpOnly(true);
        clear.setSecure(cookieSecure);
        clear.setPath("/");
        clear.setMaxAge(0);
        response.addCookie(clear);
        if ("POST".equals(request.getMethod()) && SIGNED_OUT_PATHS.contains(request.getRequestURI())) {
            chain.doFilter(request, response);
            return;
        }
        response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
        response.setContentType(MediaType.APPLICATION_JSON_VALUE);
        response.getWriter().write("{\"message\":\"" + message + "\"}");
    }
}
