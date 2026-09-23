package com.sanjose.inventory.service;

import com.sanjose.inventory.config.SpHelper;
import com.sanjose.inventory.dto.UserRequest;
import com.sanjose.inventory.dto.UserResponse;
import com.sanjose.inventory.exception.ResourceNotFoundException;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Set;

@Service
@RequiredArgsConstructor
@Transactional
public class UserService {

    private static final Set<String> VALID_ROLES = Set.of("ADMIN", "STAFF");

    // ambiguous-looking characters (0/O, 1/l/I) excluded so a printed/typed
    // temporary password isn't misread
    private static final String GEN_UPPER   = "ABCDEFGHJKLMNPQRSTUVWXYZ";
    private static final String GEN_LOWER   = "abcdefghijkmnopqrstuvwxyz";
    private static final String GEN_DIGITS  = "23456789";
    private static final String GEN_SPECIAL = "@$!%*?&_#^";
    private static final int    GEN_LENGTH  = 12;
    private static final SecureRandom RANDOM = new SecureRandom();

    private final JdbcTemplate jdbcTemplate;
    private final PasswordEncoder passwordEncoder;
    private final AuditLogService auditLogService;
    private final EmailService emailService;

    private static String resolveRole(String role, String fallback) {
        if (role == null || role.isBlank()) return fallback;
        String normalized = role.toUpperCase();
        if (!VALID_ROLES.contains(normalized)) {
            throw new IllegalArgumentException("Invalid role: " + role + " (must be ADMIN or STAFF)");
        }
        return normalized;
    }

    // guarantees at least one char from each required class, matching @StrongPassword's rules
    private static String generatePassword() {
        List<Character> chars = new ArrayList<>();
        chars.add(GEN_UPPER.charAt(RANDOM.nextInt(GEN_UPPER.length())));
        chars.add(GEN_LOWER.charAt(RANDOM.nextInt(GEN_LOWER.length())));
        chars.add(GEN_DIGITS.charAt(RANDOM.nextInt(GEN_DIGITS.length())));
        chars.add(GEN_SPECIAL.charAt(RANDOM.nextInt(GEN_SPECIAL.length())));
        String all = GEN_UPPER + GEN_LOWER + GEN_DIGITS + GEN_SPECIAL;
        for (int i = chars.size(); i < GEN_LENGTH; i++) {
            chars.add(all.charAt(RANDOM.nextInt(all.length())));
        }
        Collections.shuffle(chars, RANDOM);
        StringBuilder sb = new StringBuilder(chars.size());
        chars.forEach(sb::append);
        return sb.toString();
    }

    private static final RowMapper<UserResponse> USER_MAPPER = (rs, rn) ->
        UserResponse.builder()
            .id(rs.getLong("id"))
            .username(rs.getString("username"))
            .email(rs.getString("email"))
            .fullName(rs.getString("fullName"))
            .role(rs.getString("role"))
            .isActive(rs.getObject("isActive", Boolean.class))
            .officeId(rs.getObject("office_id", Long.class))
            .officeName(rs.getString("office_officeName"))
            .personnelId(rs.getObject("personnelId", Long.class))
            .personnelName(rs.getString("personnelName"))
            .assetCount(rs.getInt("assetCount"))
            .build();

    public List<UserResponse> findAll(String search) {
        if (search != null && !search.isBlank()) {
            return jdbcTemplate.query("CALL sp_users_search(?)", USER_MAPPER, search.trim());
        }
        return jdbcTemplate.query("CALL sp_users_get_all()", USER_MAPPER);
    }

    public UserResponse findById(Long id) {
        List<UserResponse> list = jdbcTemplate.query("CALL sp_users_get_by_id(?)", USER_MAPPER, id);
        if (list.isEmpty()) throw new ResourceNotFoundException("User not found: " + id);
        return list.get(0);
    }

    public UserResponse create(UserRequest req) {
        Boolean exists = SpHelper.callWithOutBoolean(jdbcTemplate,
            "CALL sp_users_username_exists(?, ?)", req.getUsername());
        if (Boolean.TRUE.equals(exists)) {
            throw new IllegalArgumentException("Username already exists: " + req.getUsername());
        }
        if (req.getEmail() != null && !req.getEmail().isBlank()) {
            Boolean emailExists = SpHelper.callWithOutBoolean(jdbcTemplate,
                "CALL sp_users_email_exists(?, ?, ?)", req.getEmail(), 0);
            if (Boolean.TRUE.equals(emailExists)) {
                throw new IllegalArgumentException("Email already in use: " + req.getEmail());
            }
        }
        boolean generate = Boolean.TRUE.equals(req.getGeneratePassword());
        String plainPassword;
        if (generate) {
            if (req.getEmail() == null || req.getEmail().isBlank()) {
                throw new IllegalArgumentException("Email is required to auto-generate and send a password.");
            }
            if (!emailService.isEnabled()) {
                throw new IllegalArgumentException(
                    "Email notifications aren't configured — set a password manually instead.");
            }
            plainPassword = generatePassword();
        } else {
            if (req.getPassword() == null || req.getPassword().isBlank()) {
                throw new IllegalArgumentException("Password is required.");
            }
            plainPassword = req.getPassword();
        }
        requireFreePersonnelName(req.getFullName(), null);
        String hash = passwordEncoder.encode(plainPassword);
        Long newId = SpHelper.callWithOutLong(jdbcTemplate,
            "CALL sp_users_create(?, ?, ?, ?, ?, ?, ?, ?)",
            req.getUsername(), req.getEmail(), hash, req.getFullName(),
            resolveRole(req.getRole(), "STAFF"),
            0, // office is assigned by an admin on the Personnel module
            req.getIsActive() != null ? req.getIsActive() : true);
        jdbcTemplate.update("CALL sp_personnel_sync_accounts()");
        UserResponse saved = findById(newId);
        auditLogService.log("USER_CREATED", "Users", newId, "user", "Created: " + saved.getUsername());
        if (generate) {
            String html = "<p>A San Jose GSO Inventory Management System account has been created for you.</p>"
                + "<p><b>Username:</b> " + saved.getUsername() + "</p>"
                + "<p><b>Temporary Password:</b> "
                + "<span style=\"font-family:monospace;font-size:16px;\">" + plainPassword + "</span></p>"
                + "<p>Please log in and change this password as soon as possible.</p>";
            emailService.send(saved.getEmail(), "Your San Jose GSO Inventory account has been created", html);
        }
        return saved;
    }

    public UserResponse update(Long id, UserRequest req) {
        UserResponse existing = findById(id);
        String newEmail = req.getEmail() != null ? req.getEmail() : existing.getEmail();
        if (newEmail != null && !newEmail.isBlank()) {
            Boolean emailExists = SpHelper.callWithOutBoolean(jdbcTemplate,
                "CALL sp_users_email_exists(?, ?, ?)", newEmail, id.intValue());
            if (Boolean.TRUE.equals(emailExists)) {
                throw new IllegalArgumentException("Email already in use: " + newEmail);
            }
        }
        String fullName = req.getFullName() != null ? req.getFullName() : existing.getFullName();
        requireFreePersonnelName(fullName, id);
        boolean deactivating = Boolean.TRUE.equals(existing.getIsActive()) && Boolean.FALSE.equals(req.getIsActive());
        if (deactivating) {
            guardDeactivation(existing);
            if (existing.getAssetCount() > 0) {
                throw new IllegalArgumentException("\"" + displayName(existing) + "\" still has " + existing.getAssetCount()
                    + " asset(s). Use Deactivate on the Accounts list to transfer them to another account first.");
            }
        }
        String hash = (req.getPassword() != null && !req.getPassword().isBlank())
            ? passwordEncoder.encode(req.getPassword()) : null;
        // officeId on the request is ignored — offices are assigned on the Personnel module
        jdbcTemplate.update("CALL sp_users_update(?, ?, ?, ?, ?, ?)",
            id,
            newEmail,
            fullName,
            resolveRole(req.getRole(), existing.getRole()),
            req.getIsActive() != null ? req.getIsActive() : existing.getIsActive(),
            hash);
        jdbcTemplate.update("CALL sp_personnel_sync_accounts()"); // personnel name follows the account
        if (deactivating) endSessions(id);
        UserResponse saved = findById(id);
        auditLogService.log(deactivating ? "USER_DEACTIVATED" : "USER_UPDATED", "Users", id, "user",
            (deactivating ? "Deactivated: " : "Updated: ") + saved.getUsername());
        return saved;
    }

    // Each account's personnel record carries its name, so two accounts can't share one —
    // and a rename can't take the name of another existing personnel record.
    private void requireFreePersonnelName(String fullName, Long ownUserId) {
        if (fullName == null || fullName.isBlank()) return;
        Integer clash = jdbcTemplate.queryForObject(
            "SELECT COUNT(*) FROM personnel WHERE LOWER(full_name) = LOWER(?)"
                + (ownUserId == null ? " AND user_id IS NOT NULL" : " AND (user_id IS NULL OR user_id <> ?)"),
            Integer.class,
            ownUserId == null ? new Object[]{ fullName.trim() } : new Object[]{ fullName.trim(), ownUserId });
        if (clash != null && clash > 0) {
            throw new IllegalArgumentException("A personnel record named \"" + fullName.trim() + "\" already exists.");
        }
    }

    // Accounts are deactivated, never deleted: audit logs, asset history and maintenance /
    // disposal records keep pointing at them. When staff retire or leave GSO, any assets the
    // account is accountable for or currently using are first handed to another active account
    // the admin chooses. A deactivated account can't sign in (open sessions end at once) but
    // can be reactivated from the edit form.
    public UserResponse deactivate(Long id, Long transferToUserId) {
        UserResponse user = findById(id);
        if (!Boolean.TRUE.equals(user.getIsActive())) {
            throw new IllegalArgumentException("\"" + displayName(user) + "\" is already deactivated.");
        }
        guardDeactivation(user);
        if (user.getAssetCount() > 0) {
            if (transferToUserId == null) {
                throw new IllegalArgumentException("\"" + displayName(user) + "\" still has " + user.getAssetCount()
                    + " asset(s). Choose an account to transfer them to.");
            }
            if (transferToUserId.equals(id)) {
                throw new IllegalArgumentException("Choose a different account to transfer the assets to.");
            }
            UserResponse target = findById(transferToUserId);
            if (!Boolean.TRUE.equals(target.getIsActive())) {
                throw new IllegalArgumentException("Assets can only be transferred to an active account.");
            }
            if (target.getPersonnelId() == null) jdbcTemplate.update("CALL sp_personnel_sync_accounts()");
            Long moved = SpHelper.callWithOutLong(jdbcTemplate, "CALL sp_users_transfer_assets(?, ?, ?)", id, transferToUserId);
            auditLogService.log("ASSETS_TRANSFERRED", "Users", id, "user",
                "Transferred " + moved + " asset assignment(s) from " + user.getUsername() + " to " + target.getUsername());
        }
        jdbcTemplate.update("UPDATE users SET is_active = FALSE WHERE user_id = ?", id);
        endSessions(id);
        auditLogService.log("USER_DEACTIVATED", "Users", id, "user", "Deactivated: " + user.getUsername());
        return findById(id);
    }

    private void guardDeactivation(UserResponse user) {
        String me = org.springframework.security.core.context.SecurityContextHolder.getContext().getAuthentication().getName();
        if (user.getUsername().equalsIgnoreCase(me)) {
            throw new IllegalArgumentException("You can't deactivate your own account.");
        }
        if ("ADMIN".equals(user.getRole())) {
            Integer admins = jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM users WHERE `role` = 'ADMIN' AND is_active = TRUE", Integer.class);
            if (admins != null && admins <= 1) {
                throw new IllegalArgumentException("At least one administrator account must stay active.");
            }
        }
    }

    // Bumping token_version invalidates every JWT already issued to the account (see JwtAuthFilter).
    private void endSessions(Long id) {
        jdbcTemplate.update("UPDATE users SET token_version = token_version + 1 WHERE user_id = ?", id);
    }

    private static String displayName(UserResponse u) {
        return u.getFullName() != null ? u.getFullName() : u.getUsername();
    }

    public void resetPassword(Long id, String newPassword) {
        UserResponse user = findById(id);
        jdbcTemplate.update("CALL sp_users_change_password(?, ?)",
            id, passwordEncoder.encode(newPassword));
        jdbcTemplate.update("CALL sp_auth_login_success(?)", id);
        // admin-set password is a temp password too — force the user to pick their own
        jdbcTemplate.update("UPDATE users SET must_change_password = TRUE WHERE user_id = ?", id);
        auditLogService.log("USER_PASSWORD_RESET", "Users", id, "user",
            "Password reset by administrator: " + user.getUsername());
    }

    public void changePassword(String username, String currentPassword, String newPassword) {
        List<Object[]> rows = jdbcTemplate.query(
            "CALL sp_users_get_by_username(?)",
            (rs, rn) -> new Object[]{ rs.getLong("id"), rs.getString("password") },
            username);
        if (rows.isEmpty()) throw new ResourceNotFoundException("User not found: " + username);
        Long userId = (Long) rows.get(0)[0];
        String storedHash = (String) rows.get(0)[1];
        if (!passwordEncoder.matches(currentPassword, storedHash)) {
            throw new IllegalArgumentException("Current password is incorrect");
        }
        jdbcTemplate.update("CALL sp_users_change_password(?, ?)",
            userId, passwordEncoder.encode(newPassword));
        jdbcTemplate.update("UPDATE users SET must_change_password = FALSE WHERE user_id = ?", userId);
        auditLogService.log("USER_PASSWORD_CHANGED", "Users", userId, "user",
            "Self-service password change: " + username);
    }
}
