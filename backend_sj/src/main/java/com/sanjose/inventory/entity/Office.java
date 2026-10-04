package com.sanjose.inventory.entity;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import jakarta.persistence.*;
import lombok.*;
import java.time.LocalDateTime;

@Entity
@Table(name = "offices")
@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class Office {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "office_id", columnDefinition = "INT")
    private Long id;

    @Column(name = "office_name", nullable = false, unique = true, length = 100)
    private String officeName;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "head_user_id", columnDefinition = "INT")
    @JsonIgnoreProperties({"office", "password", "failedLoginAttempts", "accountLockedUntil"})
    private User headUser;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @PrePersist
    protected void onCreate() {
        if (createdAt == null) createdAt = LocalDateTime.now();
    }
}
