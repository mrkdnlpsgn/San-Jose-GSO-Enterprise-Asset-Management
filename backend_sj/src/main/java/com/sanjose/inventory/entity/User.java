package com.sanjose.inventory.entity;

import com.fasterxml.jackson.annotation.JsonIgnore;
import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import jakarta.persistence.*;
import lombok.*;
import java.time.LocalDateTime;

@Entity
@Table(name = "users")
@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class User {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "user_id", columnDefinition = "INT")
    private Long id;

    @Column(nullable = false, unique = true, length = 50)
    private String username;

    // Used only for the forgot-password OTP flow (AuthService, via raw JDBC) — not
    // used for login. Nullable: many accounts are admin-created before an email exists.
    @Column(unique = true, length = 255)
    private String email;

    @JsonIgnore
    @Column(name = "password_hash", nullable = false)
    private String password;

    @Column(name = "full_name", nullable = false, length = 100)
    private String fullName;

    @Column(nullable = false, length = 20)
    private String role; // "ADMIN" or "STAFF"

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "office_id", columnDefinition = "INT")
    @JsonIgnoreProperties({"headUser", "users", "createdAt"})
    private Office office;

    @Builder.Default
    @Column(name = "is_active", nullable = false)
    private Boolean isActive = true;

    @Builder.Default
    @Column(name = "failed_login_attempts", nullable = false)
    private Integer failedLoginAttempts = 0;

    @Column(name = "account_locked_until")
    private LocalDateTime accountLockedUntil;

    // Bumped on every password change (self, admin-reset, forgot-password). Embedded
    // as a claim in every JWT; JwtAuthFilter rejects tokens whose claim doesn't match
    // the current value, so existing sessions can't outlive a password reset.
    @Builder.Default
    @Column(name = "token_version", nullable = false)
    private Integer tokenVersion = 0;

    // Forces a password change on next login — set on account creation and
    // admin-mediated resets, cleared once the user picks their own password.
    @Builder.Default
    @Column(name = "must_change_password", nullable = false, columnDefinition = "BOOLEAN NOT NULL DEFAULT TRUE")
    private Boolean mustChangePassword = true;

    // Set when the user acknowledges the Data Privacy Notice; null means not yet
    // acknowledged, which triggers the one-time modal on their next session.
    @Column(name = "privacy_acknowledged_at")
    private LocalDateTime privacyAcknowledgedAt;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @PrePersist
    protected void onCreate() {
        if (createdAt == null) createdAt = LocalDateTime.now();
    }
}
