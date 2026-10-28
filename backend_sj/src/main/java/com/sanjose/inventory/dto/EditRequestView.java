package com.sanjose.inventory.dto;

import java.time.LocalDateTime;

// One staff request (a maintenance or disposal record a STAFF account filed, e.g. by
// changing an asset's status, or a transfer request) as shown in Asset History's "Requests" view.
public record EditRequestView(
    String kind,              // MAINTENANCE | DISPOSAL | TRANSFER
    Long recordId,
    Long assetId,
    String propertyNumber,
    String parNumber,
    String assetDescription,
    String detail,            // maintenance findings / disposal reason / "From → To · location"
    String approvalStatus,    // PENDING_APPROVAL | APPROVED | REJECTED
    String reviewNote,
    LocalDateTime requestedAt,
    LocalDateTime reviewedAt,
    Long requestedById,
    String requestedByName,
    String reviewedByName,
    int reminderCount,                // times an Admin-Staff account reminded an admin about it
    LocalDateTime lastRemindedAt,
    String lastRemindedByName
) {
    public record Reminders(int count, LocalDateTime lastAt, String lastByName) {}

    public EditRequestView(String kind, Long recordId, Long assetId, String propertyNumber, String parNumber,
                           String assetDescription, String detail, String approvalStatus, String reviewNote,
                           LocalDateTime requestedAt, LocalDateTime reviewedAt, Long requestedById,
                           String requestedByName, String reviewedByName) {
        this(kind, recordId, assetId, propertyNumber, parNumber, assetDescription, detail, approvalStatus,
            reviewNote, requestedAt, reviewedAt, requestedById, requestedByName, reviewedByName, 0, null, null);
    }

    public EditRequestView withReminders(Reminders r) {
        return new EditRequestView(kind, recordId, assetId, propertyNumber, parNumber, assetDescription, detail,
            approvalStatus, reviewNote, requestedAt, reviewedAt, requestedById, requestedByName, reviewedByName,
            r.count(), r.lastAt(), r.lastByName());
    }
}
