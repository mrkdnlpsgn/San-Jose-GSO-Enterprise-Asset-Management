package com.sanjose.inventory.entity;

import jakarta.persistence.*;
import lombok.*;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;

@Entity
@Table(name = "device_records")
@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class DeviceRecord {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "device_id")
    private Long id;

    @Column(name = "equipment_id", nullable = false, columnDefinition = "INT")
    private Long equipmentId;

    @Column(name = "item_code", length = 50)
    private String itemCode;

    @Column(name = "serial_number", length = 100)
    private String serialNumber;

    @Column(length = 100)
    private String model;

    @Column(name = "amount_value", precision = 12, scale = 2)
    private BigDecimal amountValue;

    @Column(name = "acquisition_date")
    private LocalDate acquisitionDate;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @Column(name = "updated_at", nullable = false)
    private LocalDateTime updatedAt;

    @PrePersist
    protected void onCreate() {
        createdAt = updatedAt = LocalDateTime.now();
    }

    @PreUpdate
    protected void onUpdate() {
        updatedAt = LocalDateTime.now();
    }
}
