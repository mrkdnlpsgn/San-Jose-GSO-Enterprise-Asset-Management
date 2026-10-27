package com.sanjose.inventory.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.security.web.authentication.HttpStatusEntryPoint;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.security.web.header.writers.StaticHeadersWriter;
import org.springframework.web.client.RestTemplate;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

import java.util.Arrays;
import java.util.List;

@Configuration
@EnableWebSecurity
public class SecurityConfig {

    private final JwtAuthFilter jwtAuthFilter;
    private final RateLimitingFilter rateLimitingFilter;
    private final WebhookVerificationFilter webhookVerificationFilter;
    private final IdempotencyFilter idempotencyFilter;

    // Comma-separated list of allowed CORS origins - override via env var in production
    @Value("${cors.allowed-origins:http://localhost:3000}")
    private String allowedOriginsConfig;

    public SecurityConfig(JwtAuthFilter jwtAuthFilter,
                          RateLimitingFilter rateLimitingFilter,
                          WebhookVerificationFilter webhookVerificationFilter,
                          IdempotencyFilter idempotencyFilter) {
        this.jwtAuthFilter = jwtAuthFilter;
        this.rateLimitingFilter = rateLimitingFilter;
        this.webhookVerificationFilter = webhookVerificationFilter;
        this.idempotencyFilter = idempotencyFilter;
    }

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http
            // CSRF: disabled intentionally - JWT stored in HttpOnly cookie, not in Authorization header.
            .csrf(AbstractHttpConfigurer::disable)
            .cors(cors -> cors.configurationSource(corsConfigurationSource()))
            .sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            // Not signed in (no cookie, or it was just cleared as expired) → 401, so clients send
            // the user to sign in. Spring's default here is 403, which read as "no permission"
            // and left the mobile app stuck on error screens after the 1-hour token expired.
            // A signed-in user lacking a role still gets 403.
            .exceptionHandling(ex -> ex.authenticationEntryPoint(new HttpStatusEntryPoint(HttpStatus.UNAUTHORIZED)))
            .headers(headers -> headers
                // Clickjacking protection
                .frameOptions(frame -> frame.deny())
                // Prevent MIME-type sniffing
                .contentTypeOptions(contentType -> {})
                // Force no caching for all API responses
                .cacheControl(cache -> {})
                // HSTS: 1 year, include subdomains, eligible for browser preload list
                .httpStrictTransportSecurity(hsts -> hsts
                    .includeSubDomains(true)
                    .maxAgeInSeconds(31_536_000)
                    .preload(true))
                // Content Security Policy - strict; no inline scripts, no external resources
                .contentSecurityPolicy(csp -> csp.policyDirectives(
                    "default-src 'self'; " +
                    "script-src 'self'; " +
                    "style-src 'self' 'unsafe-inline'; " +
                    "img-src 'self' data:; " +
                    "font-src 'self'; " +
                    "connect-src 'self'; " +
                    "frame-ancestors 'none'; " +
                    "base-uri 'self'; " +
                    "form-action 'self'; " +
                    "object-src 'none';"
                ))
                // Referrer policy: send origin only on same-site; nothing cross-origin (HTTPS→HTTP)
                .addHeaderWriter(new StaticHeadersWriter(
                    "Referrer-Policy", "strict-origin-when-cross-origin"))
                // Permissions policy: deny access to sensitive browser APIs
                .addHeaderWriter(new StaticHeadersWriter(
                    "Permissions-Policy",
                    "camera=(), microphone=(), geolocation=(), payment=(), " +
                    "usb=(), fullscreen=(self), display-capture=()"))
                // DNS prefetch leaks visited URLs - disable
                .addHeaderWriter(new StaticHeadersWriter("X-DNS-Prefetch-Control", "off"))
            )
            .authorizeHttpRequests(auth -> auth
                .requestMatchers("/api/auth/**").permitAll()
                // Spring's error page: an exception anywhere is forwarded here, and if it were
                // protected every 400/404/500 would reach the client disguised as a 401/403.
                .requestMatchers("/error").permitAll()
                // Container healthcheck (Docker HEALTHCHECK hits this with no auth)
                .requestMatchers("/actuator/health").permitAll()
                // Mobile app update check: runs on app open, before sign-in
                .requestMatchers(HttpMethod.GET, "/api/app/version").permitAll()
                // Uploaded evidence photos: served as plain static files, not sensitive
                .requestMatchers(HttpMethod.GET, "/uploads/**").permitAll()
                // RBAC: ADMIN manages everything. STAFF may only view/edit/update assets of the
                // office assigned to them (office scoping is enforced in AccessService) and
                // request new maintenance/disposal records for an admin to approve.
                // Users: GET + own password change for any authenticated user; all else ADMIN only
                .requestMatchers(HttpMethod.GET, "/api/users", "/api/users/**").authenticated()
                .requestMatchers(HttpMethod.PUT, "/api/users/me/password").authenticated()
                .requestMatchers("/api/users/me/avatar").authenticated()
                .requestMatchers(HttpMethod.PUT, "/api/users/me/two-factor").authenticated()
                .requestMatchers(HttpMethod.POST, "/api/users/me/forget-devices").authenticated()
                .requestMatchers("/api/users/**").hasRole("ADMIN")
                .requestMatchers("/api/audit-logs/**").hasRole("ADMIN")
                .requestMatchers("/api/deleted-records/**").hasRole("ADMIN")
                // Assets: only ADMIN adds (incl. import and label OCR, which pre-fills Add Asset) or deletes
                .requestMatchers(HttpMethod.POST, "/api/assets", "/api/assets/bulk-import", "/api/assets/scan-label").hasRole("ADMIN")
                .requestMatchers(HttpMethod.DELETE, "/api/assets/*").hasRole("ADMIN")
                .requestMatchers("/api/assets/**", "/api/assets").authenticated()
                // Maintenance / Disposal: staff may create (as a request), edit and attach photos;
                // approving/rejecting requests and deleting records is ADMIN only
                .requestMatchers("/api/maintenance/*/approve", "/api/maintenance/*/reject",
                                 "/api/disposal/*/approve", "/api/disposal/*/reject").hasRole("ADMIN")
                .requestMatchers(HttpMethod.DELETE, "/api/maintenance/*", "/api/disposal/*").hasRole("ADMIN")
                // Transfers: anyone may file one (staff's wait for approval); approving is ADMIN only
                .requestMatchers("/api/transfers/*/approve", "/api/transfers/*/reject").hasRole("ADMIN")
                .requestMatchers("/api/transfers/**", "/api/transfers").authenticated()
                .requestMatchers("/api/maintenance/**", "/api/maintenance").authenticated()
                .requestMatchers("/api/disposal/**", "/api/disposal").authenticated()
                // Reference data: readable by everyone (form dropdowns), managed by ADMIN
                .requestMatchers(HttpMethod.GET, "/api/offices/**", "/api/offices",
                                 "/api/categories/**", "/api/categories",
                                 "/api/articles/**", "/api/articles",
                                 "/api/personnel/**", "/api/personnel").authenticated()
                .requestMatchers("/api/offices/**", "/api/offices",
                                 "/api/categories/**", "/api/categories",
                                 "/api/articles/**", "/api/articles",
                                 "/api/personnel/**", "/api/personnel").hasRole("ADMIN")
                .requestMatchers("/api/equipment/**", "/api/equipment").hasRole("ADMIN")
                .requestMatchers("/api/property-numbers/**").hasRole("ADMIN")
                // Asset history: office-scoped in the service
                .requestMatchers("/api/asset-history/**").authenticated()
                // SSE stream for real-time updates (events filtered per office)
                .requestMatchers("/api/events/**").authenticated()
                // All other endpoints: any authenticated user
                .anyRequest().authenticated()
            )
            // Filter order: rate-limit → webhook-verify → JWT-auth → idempotency → Spring auth
            // (idempotency needs to run after JWT-auth so SecurityContextHolder already
            // has the authenticated principal to scope the key by)
            .addFilterBefore(rateLimitingFilter,           UsernamePasswordAuthenticationFilter.class)
            .addFilterBefore(webhookVerificationFilter,    UsernamePasswordAuthenticationFilter.class)
            .addFilterBefore(jwtAuthFilter,                UsernamePasswordAuthenticationFilter.class)
            .addFilterAfter(idempotencyFilter,             JwtAuthFilter.class);
        return http.build();
    }

    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }

    @Bean
    public RestTemplate restTemplate() {
        return new RestTemplate();
    }

    @Bean
    public CorsConfigurationSource corsConfigurationSource() {
        CorsConfiguration config = new CorsConfiguration();

        // Parse comma-separated origins - reject wildcard which is incompatible with credentials
        List<String> origins = Arrays.stream(allowedOriginsConfig.split(","))
                .map(String::trim)
                .filter(s -> !s.isBlank())
                .toList();
        if (origins.contains("*")) {
            throw new IllegalStateException(
                "cors.allowed-origins must not contain '*' when credentials are enabled. " +
                "Set explicit origins in application.properties or the CORS_ALLOWED_ORIGINS env var.");
        }
        config.setAllowedOrigins(origins);
        config.setAllowCredentials(true);

        config.setAllowedMethods(List.of("GET", "POST", "PUT", "DELETE", "OPTIONS"));
        config.setAllowedHeaders(List.of(
            "Content-Type", "Authorization", "X-Requested-With", "Accept",
            // Webhook headers - needed when frontend simulates scanner hardware
            "X-Webhook-Signature-256", "X-Webhook-Timestamp", "X-Webhook-Id",
            // Lets clients opt individual create requests into duplicate-submission protection
            "Idempotency-Key"
        ));
        // Expose rate-limit headers so clients can handle back-pressure gracefully
        config.setExposedHeaders(List.of("Retry-After", "X-RateLimit-Reset"));
        config.setMaxAge(3600L);

        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/api/**", config);
        return source;
    }
}
