package com.sanjose.inventory.entity;

import jakarta.persistence.*;
import lombok.*;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

@Entity
@Table(name = "equipment_records")
@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class EquipmentRecord {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "equipment_id", columnDefinition = "INT")
    private Long id;

    @Column(nullable = false, length = 50)
    private String type;

    @Column(name = "equipment_type", nullable = false, length = 100)
    private String equipmentType;

    @Column(name = "item_code", nullable = false, length = 50)
    private String itemCode;

    @Column(nullable = false, length = 255)
    private String article;

    @Column(nullable = false, length = 255)
    private String office;

    @Column(nullable = false, length = 255)
    private String location;

    @Column(columnDefinition = "TEXT")
    private String description;

    @Column(name = "accountable_person", nullable = false, length = 150)
    private String accountablePerson;

    @Column(name = "accountable_person_phone", length = 50)
    private String accountablePersonPhone;

    @Column(name = "accountable_person_email", length = 150)
    private String accountablePersonEmail;

    @Builder.Default
    @Column(name = "device_count", nullable = false)
    private Integer deviceCount = 0;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @Column(name = "updated_at", nullable = false)
    private LocalDateTime updatedAt;

    @Transient
    private List<DeviceRecord> devices = new ArrayList<>();

    @PrePersist
    protected void onCreate() {
        createdAt = updatedAt = LocalDateTime.now();
    }

    @PreUpdate
    protected void onUpdate() {
        updatedAt = LocalDateTime.now();
    }
}
