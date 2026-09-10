package com.sanjose.inventory.entity;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import jakarta.persistence.*;
import lombok.*;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;

@Entity
@Table(name = "disposal_ledger")
@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class DisposalLedger {

    public enum DisposalMethod { SALE, TRANSFER, DESTRUCTION, OTHERS }
    public enum DisposalStatus { PENDING, APPROVED, COMPLETED }

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "disposal_id")
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "asset_id", nullable = false)
    @JsonIgnoreProperties({"category", "office", "accountablePerson", "remarks", "qrCodePath", "sha256Hash"})
    private Asset asset;

    @Column(nullable = false, columnDefinition = "TEXT")
    private String reason;

    @Column(name = "inspection_findings", nullable = false, columnDefinition = "TEXT")
    private String inspectionFindings;

    @Enumerated(EnumType.STRING)
    @Column(name = "recommended_method", nullable = false)
    private DisposalMethod recommendedMethod;

    @Builder.Default
    @Enumerated(EnumType.STRING)
    @Column(name = "disposal_status", nullable = false)
    private DisposalStatus disposalStatus = DisposalStatus.PENDING;

    @Column(name = "inspection_date", nullable = false)
    private LocalDate inspectionDate;

    @Column(name = "approved_by", length = 150)
    private String approvedBy;

    @Column(name = "appraised_value", precision = 12, scale = 2)
    private BigDecimal appraisedValue;

    @Column(name = "or_number", length = 50)
    private String orNumber;

    @Column(precision = 12, scale = 2)
    private BigDecimal amount;

    // Computed on read from the linked asset (see DepreciationCalculator) — matches
    // the "Accumulated Depreciation" / "Carrying Amount" columns on the paper IIRUP
    // form. Informational only; disposal eligibility is gated on asset condition.
    @Transient
    private BigDecimal accumulatedDepreciation;

    @Transient
    private BigDecimal carryingAmount;

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
