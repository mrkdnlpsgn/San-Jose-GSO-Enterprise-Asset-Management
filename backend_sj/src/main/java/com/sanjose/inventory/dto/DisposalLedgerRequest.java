package com.sanjose.inventory.dto;

import lombok.Data;
import java.math.BigDecimal;
import java.time.LocalDate;

@Data
public class DisposalLedgerRequest {
    private Long assetId;
    private String reason;
    private String inspectionFindings;
    private String recommendedMethod; // SALE | TRANSFER | DESTRUCTION | OTHERS
    private String disposalStatus;    // PENDING | APPROVED | COMPLETED
    private LocalDate inspectionDate;
    private String approvedBy;
    private BigDecimal appraisedValue;
    private String orNumber;
    private BigDecimal amount;
}
