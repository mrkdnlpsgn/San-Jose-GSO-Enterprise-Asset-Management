package com.sanjose.inventory.controller;

import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.core.userdetails.UserDetails;
import com.sanjose.inventory.service.AuditLogService;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.sql.Timestamp;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

// The My Account page: the signed-in user's own details and their latest actions from the
// audit log. Only ever the caller's own rows, so staff can use it too (the full audit log
// stays admin-only).
@RestController
@RequestMapping("/api/users/me")
@RequiredArgsConstructor
public class MyAccountController {

    private static final int RECENT_LIMIT = 6;

    private final JdbcTemplate jdbcTemplate;
    private final PasswordEncoder passwordEncoder;
    private final AuditLogService auditLogService;

    public record TwoFactorRequest(Boolean enabled, String currentPassword) {}

    // Forget every computer remembered for 2-step ("Don't ask for a code for 30 days"). Remembered
    // devices are tied to token_version (TrustedDeviceService), so bumping it forgets them all —
    // and, like a password change, ends every session too, this one included.
    @PostMapping("/forget-devices")
    public ResponseEntity<Void> forgetDevices(@AuthenticationPrincipal UserDetails principal) {
        if (principal == null) return ResponseEntity.status(401).build();
        List<Long> ids = jdbcTemplate.query("SELECT user_id FROM users WHERE LOWER(username) = LOWER(?)",
            (rs, rn) -> rs.getLong(1), principal.getUsername());
        if (ids.isEmpty()) return ResponseEntity.status(401).build();
        jdbcTemplate.update("UPDATE users SET token_version = token_version + 1 WHERE user_id = ?", ids.get(0));
        auditLogService.log("USER_DEVICES_FORGOTTEN", "Users", ids.get(0), "user",
            "Forgot all remembered devices (signed out everywhere)");
        return ResponseEntity.ok().build();
    }

    // Turn the email code at sign-in on or off for your own account. On needs an email to send
    // the code to; off needs the current password, so someone at an unlocked PC can't quietly
    // remove it.
    @PutMapping("/two-factor")
    public ResponseEntity<Map<String, Object>> setTwoFactor(@AuthenticationPrincipal UserDetails principal,
                                                            @RequestBody TwoFactorRequest req) {
        if (principal == null) return ResponseEntity.status(401).build();
        if (req == null || req.enabled() == null) throw new IllegalArgumentException("Say whether to turn it on or off.");

        List<Map<String, Object>> rows = jdbcTemplate.queryForList(
            "SELECT user_id, email, password_hash, two_factor_enabled FROM users WHERE LOWER(username) = LOWER(?)",
            principal.getUsername());
        if (rows.isEmpty()) return ResponseEntity.status(401).build();
        Map<String, Object> u = rows.get(0);
        long userId = ((Number) u.get("user_id")).longValue();
        String email = (String) u.get("email");
        boolean enable = req.enabled();

        if (enable && (email == null || email.isBlank())) {
            throw new IllegalArgumentException(
                "2-step verification sends a code to your email, and this account has none. Ask the system administrator to add one.");
        }
        if (!enable && (req.currentPassword() == null
                || !passwordEncoder.matches(req.currentPassword(), (String) u.get("password_hash")))) {
            throw new IllegalArgumentException("Your current password is incorrect.");
        }
        jdbcTemplate.update("UPDATE users SET two_factor_enabled = ? WHERE user_id = ?", enable, userId);
        auditLogService.log(enable ? "USER_2FA_ENABLED" : "USER_2FA_DISABLED", "Users", userId, "user",
            "Turned 2-step verification " + (enable ? "on" : "off") + " for own account");
        return ResponseEntity.ok(Map.of("twoFactorEnabled", enable));
    }

    @GetMapping("/overview")
    public ResponseEntity<Map<String, Object>> overview(@AuthenticationPrincipal UserDetails principal) {
        if (principal == null) return ResponseEntity.status(401).build();

        List<Map<String, Object>> rows = jdbcTemplate.query(
            "SELECT u.user_id, u.email, u.created_at, u.two_factor_enabled, o.office_name "
                + "FROM users u LEFT JOIN offices o ON o.office_id = u.office_id WHERE LOWER(u.username) = LOWER(?)",
            (rs, rn) -> {
                Map<String, Object> m = new LinkedHashMap<>();
                m.put("id", rs.getLong("user_id"));
                m.put("email", rs.getString("email"));
                Timestamp created = rs.getTimestamp("created_at");
                m.put("memberSince", created != null ? created.toLocalDateTime() : null);
                m.put("twoFactorEnabled", rs.getBoolean("two_factor_enabled"));
                m.put("officeName", rs.getString("office_name"));
                return m;
            }, principal.getUsername());
        if (rows.isEmpty()) return ResponseEntity.status(401).build();
        Map<String, Object> out = rows.get(0);

        out.put("recentActivity", jdbcTemplate.query(
            "SELECT action, module, details, logged_at FROM audit_logs WHERE user_id = ? "
                + "ORDER BY logged_at DESC, log_id DESC LIMIT " + RECENT_LIMIT,
            (rs, rn) -> {
                Map<String, Object> a = new LinkedHashMap<>();
                a.put("action", rs.getString("action"));
                a.put("module", rs.getString("module"));
                a.put("details", rs.getString("details"));
                Timestamp at = rs.getTimestamp("logged_at");
                a.put("loggedAt", at != null ? at.toLocalDateTime() : null);
                return a;
            }, out.get("id")));
        out.remove("id");
        return ResponseEntity.ok(out);
    }
}
