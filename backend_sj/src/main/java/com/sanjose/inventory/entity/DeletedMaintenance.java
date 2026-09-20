package com.sanjose.inventory.entity;

import jakarta.persistence.*;
import lombok.*;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;

@Entity
@Table(name = "deleted_maintenance")
@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class DeletedMaintenance {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "deleted_maintenance_id")
    private Long id;

    @Column(name = "maintenance_id", nullable = false)
    private Long maintenanceId;

    @Column(name = "asset_id", nullable = false)
    private Long assetId;

    @Column(name = "property_number", nullable = false, length = 50)
    private String propertyNumber;

    @Column(name = "par_number", length = 50)
    private String parNumber;

    @Column(name = "asset_description", nullable = false, length = 255)
    private String assetDescription;

    @Column(name = "maintenance_type", nullable = false, length = 20)
    private String maintenanceType;

    @Column(nullable = false, columnDefinition = "TEXT")
    private String findings;

    @Column(name = "actions_taken", nullable = false, columnDefinition = "TEXT")
    private String actionsTaken;

    @Column(name = "assigned_to_user_id")
    private Long assignedToUserId;

    @Column(name = "assigned_to_name", length = 100)
    private String assignedToName;

    @Column(name = "maintenance_date", nullable = false)
    private LocalDate maintenanceDate;

    @Column(precision = 10, scale = 2)
    private BigDecimal cost;

    @Column(nullable = false, length = 20)
    private String status;

    @Column(name = "recorded_by_user_id", nullable = false)
    private Long recordedByUserId;

    @Column(name = "recorded_by_name", nullable = false, length = 100)
    private String recordedByName;

    @Column(name = "original_created_at", nullable = false)
    private LocalDateTime originalCreatedAt;

    @Column(name = "deleted_by_user_id", nullable = false)
    private Long deletedByUserId;

    @Column(name = "deleted_by_username", nullable = false, length = 50)
    private String deletedByUsername;

    @Column(name = "delete_reason", columnDefinition = "TEXT")
    private String deleteReason;

    @Column(name = "deleted_at", nullable = false)
    private LocalDateTime deletedAt;

    @PrePersist
    protected void onCreate() {
        if (deletedAt == null) deletedAt = LocalDateTime.now();
    }
}
