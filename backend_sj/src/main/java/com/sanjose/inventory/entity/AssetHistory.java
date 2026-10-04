package com.sanjose.inventory.entity;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import jakarta.persistence.*;
import lombok.*;
import java.time.LocalDateTime;

@Entity
@Table(name = "asset_history")
@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class AssetHistory {

    public enum EventType { REGISTERED, ASSIGNED, TRANSFERRED, MAINTENANCE, DISPOSAL, ARCHIVED }

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "history_id")
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "asset_id", nullable = false, columnDefinition = "INT")
    @JsonIgnoreProperties({"category", "office", "accountablePerson", "remarks", "qrCodePath", "sha256Hash"})
    private Asset asset;

    @Enumerated(EnumType.STRING)
    @Column(name = "event_type", nullable = false)
    private EventType eventType;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "from_office_id", columnDefinition = "INT")
    @JsonIgnoreProperties({"headUser", "createdAt"})
    private Office fromOffice;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "to_office_id", columnDefinition = "INT")
    @JsonIgnoreProperties({"headUser", "createdAt"})
    private Office toOffice;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "performed_by", nullable = false, columnDefinition = "INT")
    @JsonIgnoreProperties({"password", "office", "failedLoginAttempts", "accountLockedUntil"})
    private User performedBy;

    @Column(name = "event_date", nullable = false)
    private LocalDateTime eventDate;

    @Column(columnDefinition = "TEXT")
    private String notes;

    @PrePersist
    protected void onCreate() {
        if (eventDate == null) eventDate = LocalDateTime.now();
    }
}
