package com.sanjose.inventory.controller;

import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.core.userdetails.UserDetails;
import com.sanjose.inventory.config.JwtUtil;
import com.sanjose.inventory.dto.UserRequest;
import jakarta.servlet.http.Cookie;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.beans.factory.annotation.Value;
import com.sanjose.inventory.dto.UserResponse;
import com.sanjose.inventory.service.AuditLogService;
import com.sanjose.inventory.service.UserService;
import com.sanjose.inventory.service.OfficeAssignmentService;
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
    private final OfficeAssignmentService officeAssignments;
    private final AuditLogService auditLogService;
    private final UserService userService;
    private final JwtUtil jwtUtil;

    // the same session cookie settings as AuthController
    @Value("${jwt.expiration:28800000}")
    private int jwtExpiration;
    @Value("${cookie.secure:false}")
    private boolean cookieSecure;

    public record TwoFactorRequest(Boolean enabled, String currentPassword) {}
    public record DetailsRequest(String fullName, String username, String email, String currentPassword) {}

    private static final java.util.regex.Pattern EMAIL = java.util.regex.Pattern.compile("^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$");
    // No "@": the sign-in box takes a username or an email, so a username must never look like one.
    private static final java.util.regex.Pattern USERNAME = java.util.regex.Pattern.compile("^[A-Za-z0-9._-]{3,50}$");

    // Change your own full name, username and email. Needs the current password, so someone at an
    // unlocked PC can't take over the account (sign-in name, password resets and codes). The office
    // stays with the admin (Personnel page). Name and email go through the same update as the
    // Accounts page, so its checks apply: the email is not already used, the name doesn't clash
    // with another person, 2-step keeps an email.
    // Sessions are keyed to the username, so a new one gets this browser a new session cookie;
    // devices still signed in under the old name are signed out at their next request.
    @PutMapping("/details")
    public ResponseEntity<Map<String, Object>> updateDetails(@AuthenticationPrincipal UserDetails principal,
                                                             @RequestBody DetailsRequest req,
                                                             HttpServletResponse response) {
        if (principal == null) return ResponseEntity.status(401).build();
        List<Map<String, Object>> rows = jdbcTemplate.queryForList(
            "SELECT user_id, username, password_hash, token_version FROM users WHERE LOWER(username) = LOWER(?)",
            principal.getUsername());
        if (rows.isEmpty()) return ResponseEntity.status(401).build();
        Map<String, Object> me = rows.get(0);
        long userId = ((Number) me.get("user_id")).longValue();
        String oldUsername = (String) me.get("username");

        String fullName = req == null || req.fullName() == null ? "" : req.fullName().trim().replaceAll("\\s+", " ");
        String username = req == null || req.username() == null ? oldUsername : req.username().trim();
        String email = req == null || req.email() == null ? "" : req.email().trim();
        if (fullName.isEmpty()) throw new IllegalArgumentException("Enter your full name.");
        if (fullName.length() > 100) throw new IllegalArgumentException("The full name can be at most 100 characters.");
        if (!USERNAME.matcher(username).matches()) {
            throw new IllegalArgumentException("A username is 3 to 50 letters, numbers, dots, dashes or underscores, with no spaces.");
        }
        boolean renaming = !username.equals(oldUsername);
        if (renaming && !username.equalsIgnoreCase(oldUsername)) {
            Integer taken = jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM users WHERE LOWER(username) = LOWER(?) AND user_id <> ?", Integer.class, username, userId);
            if (taken != null && taken > 0) throw new IllegalArgumentException("The username \"" + username + "\" is already taken.");
        }
        if (!email.isEmpty() && (email.length() > 100 || !EMAIL.matcher(email).matches())) {
            throw new IllegalArgumentException("Enter a valid email address, like name@example.com.");
        }
        if (req.currentPassword() == null || !passwordEncoder.matches(req.currentPassword(), (String) me.get("password_hash"))) {
            throw new IllegalArgumentException("Your current password is incorrect.");
        }

        // Name and email first: if they're refused, the username (and this session) stay as they were.
        UserRequest update = new UserRequest();
        update.setFullName(fullName);
        update.setEmail(email); // blank removes it
        UserResponse saved = userService.update(userId, update);

        if (renaming) {
            jdbcTemplate.update("UPDATE users SET username = ? WHERE user_id = ?", username, userId);
            auditLogService.log("USERNAME_CHANGED", "Users", userId, "user",
                "Changed own username from " + oldUsername + " to " + username);
            Cookie cookie = new Cookie("jwt", jwtUtil.generateToken(username, ((Number) me.get("token_version")).intValue()));
            cookie.setHttpOnly(true);
            cookie.setSecure(cookieSecure);
            cookie.setPath("/");
            cookie.setMaxAge(jwtExpiration / 1000);
            response.addCookie(cookie);
        }
        return ResponseEntity.ok(Map.of("fullName", saved.getFullName(), "username", username,
            "email", saved.getEmail() == null ? "" : saved.getEmail()));
    }

    // Forget every computer remembered for 2-step ("Don't ask for a code for 30 days"). Remembered
    // devices are tied to token_version (TrustedDeviceService), so bumping it forgets them all -
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
        String offices = OfficeAssignmentService.names(officeAssignments.ofUser((Long) out.get("id")));
        if (offices != null) out.put("officeName", offices);

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
