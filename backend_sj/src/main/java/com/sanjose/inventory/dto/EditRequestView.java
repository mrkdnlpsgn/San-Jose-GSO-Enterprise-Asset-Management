package com.sanjose.inventory.dto;

import java.time.LocalDateTime;

// One staff request (a maintenance or disposal record a STAFF account filed, e.g. by
// changing an asset's status) as shown in Asset History's "Requests" view.
public record EditRequestView(
    String kind,              // MAINTENANCE | DISPOSAL
    Long recordId,
    Long assetId,
    String propertyNumber,
    String parNumber,
    String assetDescription,
    String detail,            // maintenance findings / disposal reason
    String approvalStatus,    // PENDING_APPROVAL | APPROVED | REJECTED
    String reviewNote,
    LocalDateTime requestedAt,
    LocalDateTime reviewedAt,
    Long requestedById,
    String requestedByName,
    String reviewedByName
) {}
