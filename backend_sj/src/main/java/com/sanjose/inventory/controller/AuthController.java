package com.sanjose.inventory.controller;

import com.sanjose.inventory.dto.ForceChangePasswordRequest;
import com.sanjose.inventory.dto.ForgotPasswordConfirmRequest;
import com.sanjose.inventory.dto.ForgotPasswordRequest;
import com.sanjose.inventory.dto.LoginVerifyOtpRequest;
import com.sanjose.inventory.service.AuthService;
import jakarta.servlet.http.Cookie;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDateTime;
import java.util.Map;

@RestController
@RequestMapping("/api/auth")
@RequiredArgsConstructor
public class AuthController {

    @Value("${jwt.expiration:28800000}")
    private int jwtExpiration;

    @Value("${cookie.secure:false}")
    private boolean cookieSecure;

    private final AuthService authService;

    @PostMapping("/login")
    public ResponseEntity<Map<String, Object>> login(@RequestBody Map<String, String> body,
                                                      HttpServletResponse response) {
        String identifier = body.get("identifier");
        String password   = body.get("password");
        Map<String, Object> result = authService.login(identifier, password);

        // Correct credentials, but a temp password — no session yet, frontend must
        // collect a new password via /force-change-password before one is issued.
        if (Boolean.TRUE.equals(result.get("mustChangePassword"))) {
            return ResponseEntity.ok(Map.of(
                "mustChangePassword", true,
                "username", result.get("username")));
        }

        // Correct credentials, but 2FA is enabled on this account — no session yet,
        // frontend must collect the emailed code via /login/verify-otp.
        if (Boolean.TRUE.equals(result.get("requiresTwoFactor"))) {
            return ResponseEntity.ok(Map.of(
                "requiresTwoFactor", true,
                "username", result.get("username")));
        }

        setSessionCookie(response, (String) result.get("token"));
        return ResponseEntity.ok(Map.of("user", result.get("user")));
    }

    @PostMapping("/login/verify-otp")
    public ResponseEntity<Map<String, Object>> verifyLoginOtp(@Valid @RequestBody LoginVerifyOtpRequest req,
                                                               HttpServletResponse response) {
        Map<String, Object> result = authService.verifyLoginOtp(req.identifier(), req.otp());
        setSessionCookie(response, (String) result.get("token"));
        return ResponseEntity.ok(Map.of("user", result.get("user")));
    }

    @PostMapping("/force-change-password")
    public ResponseEntity<Map<String, Object>> forceChangePassword(@Valid @RequestBody ForceChangePasswordRequest req,
                                                                    HttpServletResponse response) {
        Map<String, Object> result = authService.forceChangePassword(
            req.identifier(), req.currentPassword(), req.newPassword());

        setSessionCookie(response, (String) result.get("token"));
        return ResponseEntity.ok(Map.of("user", result.get("user")));
    }

    private void setSessionCookie(HttpServletResponse response, String token) {
        Cookie cookie = new Cookie("jwt", token);
        cookie.setHttpOnly(true);
        cookie.setSecure(cookieSecure);
        cookie.setPath("/");
        cookie.setMaxAge(jwtExpiration / 1000);
        response.addCookie(cookie);
    }

    @PostMapping("/logout")
    public ResponseEntity<Void> logout(HttpServletResponse response) {
        Cookie cookie = new Cookie("jwt", "");
        cookie.setHttpOnly(true);
        cookie.setSecure(cookieSecure);
        cookie.setPath("/");
        cookie.setMaxAge(0);
        response.addCookie(cookie);
        return ResponseEntity.ok().build();
    }

    @PostMapping("/forgot-password/request")
    public ResponseEntity<Map<String, String>> requestPasswordReset(@Valid @RequestBody ForgotPasswordRequest req) {
        authService.requestPasswordReset(req.username());
        return ResponseEntity.ok(Map.of("message",
            "If an account with that username has an email on file, a verification code has been sent to it."));
    }

    @PostMapping("/forgot-password/confirm")
    public ResponseEntity<Map<String, String>> confirmPasswordReset(@Valid @RequestBody ForgotPasswordConfirmRequest req) {
        authService.confirmPasswordReset(req.username(), req.otp(), req.newPassword());
        return ResponseEntity.ok(Map.of("message", "Password reset successfully."));
    }

    @GetMapping("/me")
    public ResponseEntity<Map<String, Object>> me(@AuthenticationPrincipal UserDetails principal) {
        if (principal == null) return ResponseEntity.status(401).build();
        Map<String, Object> userMap = authService.getCurrentUserMap(principal.getUsername());
        if (userMap == null) return ResponseEntity.status(401).build();
        return ResponseEntity.ok(userMap);
    }

    @PostMapping("/acknowledge-privacy")
    public ResponseEntity<Map<String, Object>> acknowledgePrivacy(@AuthenticationPrincipal UserDetails principal) {
        if (principal == null) return ResponseEntity.status(401).build();
        LocalDateTime ack = authService.acknowledgePrivacy(principal.getUsername());
        return ResponseEntity.ok(Map.of("privacyAcknowledgedAt", ack));
    }
}
