package com.sanjose.inventory.controller;

import com.sanjose.inventory.service.AuditLogService;
import com.sanjose.inventory.service.ProfilePictureService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

// Each signed-in user manages only their own picture.
@RestController
@RequestMapping("/api/users/me/avatar")
@RequiredArgsConstructor
public class ProfilePictureController {

    private final ProfilePictureService profilePictureService;
    private final AuditLogService auditLogService;
    private final JdbcTemplate jdbcTemplate;

    @PostMapping(consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public ResponseEntity<Map<String, Object>> upload(@AuthenticationPrincipal UserDetails principal,
                                                      @RequestParam("file") MultipartFile file) {
        Long userId = currentUserId(principal);
        String url = profilePictureService.replace(userId, file);
        auditLogService.log("PROFILE_PICTURE_CHANGED", "Users", userId, "user", "Updated profile picture");
        return ResponseEntity.ok(body(url));
    }

    @DeleteMapping
    public ResponseEntity<Map<String, Object>> remove(@AuthenticationPrincipal UserDetails principal) {
        Long userId = currentUserId(principal);
        profilePictureService.remove(userId);
        auditLogService.log("PROFILE_PICTURE_REMOVED", "Users", userId, "user", "Removed profile picture");
        return ResponseEntity.ok(body(null));
    }

    private Map<String, Object> body(String url) {
        Map<String, Object> m = new HashMap<>();   // Map.of rejects a null value
        m.put("avatarUrl", url);
        return m;
    }

    private Long currentUserId(UserDetails principal) {
        if (principal == null) throw new BadCredentialsException("Not signed in");
        List<Long> ids = jdbcTemplate.query("CALL sp_users_get_by_username(?)",
            (rs, rn) -> rs.getLong("id"), principal.getUsername());
        if (ids.isEmpty()) throw new BadCredentialsException("Not signed in");
        return ids.get(0);
    }
}
