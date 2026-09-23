package com.sanjose.inventory.entity;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import jakarta.persistence.*;
import lombok.*;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;

@Entity
@Table(name = "maintenance_ledger")
@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class MaintenanceLedger {

    public enum MaintenanceType { PREVENTIVE, CORRECTIVE, REPAIR }
    public enum MaintenanceStatus { COMPLETED, ONGOING, SCHEDULED }

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "maintenance_id")
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "asset_id", nullable = false)
    @JsonIgnoreProperties({"category", "office", "accountablePerson", "remarks", "qrCodePath", "sha256Hash"})
    private Asset asset;

    @Enumerated(EnumType.STRING)
    @Column(name = "maintenance_type", nullable = false)
    private MaintenanceType maintenanceType;

    @Column(nullable = false, columnDefinition = "TEXT")
    private String findings;

    @Column(name = "actions_taken", nullable = false, columnDefinition = "TEXT")
    private String actionsTaken;

    @Column(name = "assigned_to", length = 150)
    private String assignedTo;

    // PENDING_APPROVAL (requested by staff) | APPROVED | REJECTED — see AccessService
    @Column(name = "approval_status", length = 20)
    private String approvalStatus;

    @Column(name = "review_note", length = 255)
    private String reviewNote;

    @Transient
    private String requestedByName;

    @Column(name = "maintenance_date", nullable = false)
    private LocalDate maintenanceDate;

    @Column(precision = 10, scale = 2)
    private BigDecimal cost;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private MaintenanceStatus status;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "recorded_by", nullable = false)
    @JsonIgnoreProperties({"password", "office", "failedLoginAttempts", "accountLockedUntil"})
    private User recordedBy;

    @Builder.Default
    @Column(name = "is_deleted", nullable = false)
    private Boolean isDeleted = false;

    @Column(name = "deleted_at")
    private LocalDateTime deletedAt;

    @Column(name = "deleted_by")
    private Long deletedBy;

    @Column(name = "delete_reason", columnDefinition = "TEXT")
    private String deleteReason;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @Column(name = "updated_at", nullable = false)
    private LocalDateTime updatedAt;

    @PrePersist
    protected void onCreate() {
        if (createdAt == null) createdAt = LocalDateTime.now();
        if (updatedAt == null) updatedAt = createdAt;
    }

    @PreUpdate
    protected void onUpdate() {
        updatedAt = LocalDateTime.now();
    }
}
