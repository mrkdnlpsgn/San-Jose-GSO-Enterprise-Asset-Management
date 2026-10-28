package com.sanjose.inventory.dto;

import lombok.Data;
import java.math.BigDecimal;
import java.time.LocalDate;

@Data
public class MaintenanceLedgerRequest {
    private Long assetId;
    private String maintenanceType; // PREVENTIVE | CORRECTIVE | REPAIR
    private String findings;
    private String actionsTaken;
    private String assignedTo;
    private LocalDate maintenanceDate;
    private BigDecimal cost;
    private String status; // COMPLETED | ONGOING | SCHEDULED
    // Parts and labor lines; when there are any, the cost is their sum. null keeps a record's
    // lines as they are (older app versions don't send them).
    private java.util.List<MaintenanceItem> items;
}
