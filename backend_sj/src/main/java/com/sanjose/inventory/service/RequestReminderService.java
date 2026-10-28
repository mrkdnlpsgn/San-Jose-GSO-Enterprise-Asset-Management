package com.sanjose.inventory.service;

import com.sanjose.inventory.dto.EditRequestView;
import com.sanjose.inventory.exception.ForbiddenException;
import com.sanjose.inventory.exception.ResourceNotFoundException;
import jakarta.annotation.PostConstruct;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.sql.Timestamp;
import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

// "Notify admin" on a pending staff request: an Admin-Staff account can't approve requests, but
// can nudge an administrator about one that is still waiting. Each reminder is kept, so the
// admin's notification bell (web and mobile) shows the request with who reminded and how often;
// the reminders count stays on the request once it is reviewed, but only pending ones notify.
@Service
@RequiredArgsConstructor
@Transactional
public class RequestReminderService {

    // One reminder per request per hour, from anyone - enough to nudge, not enough to spam.
    private static final int COOLDOWN_MINUTES = 60;

    private final JdbcTemplate jdbcTemplate;
    private final AccessService accessService;
    private final AuditLogService auditLogService;
    private final SseEmitterService sseEmitterService;

    // Created here rather than in a migration script so a fresh or hosted database
    // (Render/Aiven, where Hibernate DDL is off) gets it on the next deploy.
    @PostConstruct
    void ensureTable() {
        jdbcTemplate.execute("""
            CREATE TABLE IF NOT EXISTS request_reminders (
              reminder_id  INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
              kind         VARCHAR(20) NOT NULL,
              record_id    INT NOT NULL,
              reminded_by  INT NOT NULL,
              reminded_at  DATETIME NOT NULL,
              KEY idx_reminder_request (kind, record_id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
            """);
    }

    private record Target(String table, String idColumn, String statusColumn, boolean softDeleted) {}

    private static final Map<String, Target> TARGETS = Map.of(
        "MAINTENANCE", new Target("maintenance_ledger", "maintenance_id", "approval_status", true),
        "DISPOSAL", new Target("disposal_ledger", "disposal_id", "approval_status", true),
        "TRANSFER", new Target("asset_transfer_requests", "transfer_id", "status", false));

    public Map<String, Object> remind(String kind, Long recordId) {
        AccessService.CurrentUser me = accessService.current();
        if (!AccessService.ROLE_ADMIN_STAFF.equalsIgnoreCase(roleOf(me.id()))) {
            throw new ForbiddenException("Only an Admin-Staff account can remind an administrator about a request.");
        }
        String k = kind == null ? "" : kind.trim().toUpperCase();
        Target t = TARGETS.get(k);
        if (t == null) throw new IllegalArgumentException("Unknown request type: " + kind);

        List<Object[]> rows = jdbcTemplate.query(
            "SELECT r.asset_id, r." + t.statusColumn() + ", a.property_number FROM " + t.table() + " r"
                + " JOIN assets a ON a.asset_id = r.asset_id WHERE r." + t.idColumn() + " = ?"
                + (t.softDeleted() ? " AND r.is_deleted = 0" : ""),
            (rs, rn) -> new Object[]{ rs.getLong(1), rs.getString(2), rs.getString(3) }, recordId);
        if (rows.isEmpty()) throw new ResourceNotFoundException("Request not found.");
        Long assetId = (Long) rows.get(0)[0];
        String status = (String) rows.get(0)[1];
        String propertyNumber = (String) rows.get(0)[2];
        if (!"PENDING_APPROVAL".equals(status)) {
            throw new IllegalStateException("This request was already " + (status == null ? "reviewed" : status.toLowerCase()) + ".");
        }

        LocalDateTime now = LocalDateTime.now();
        List<Timestamp> last = jdbcTemplate.query(
            "SELECT MAX(reminded_at) FROM request_reminders WHERE kind = ? AND record_id = ?",
            (rs, rn) -> rs.getTimestamp(1), k, recordId);
        if (!last.isEmpty() && last.get(0) != null) {
            LocalDateTime next = last.get(0).toLocalDateTime().plusMinutes(COOLDOWN_MINUTES);
            if (now.isBefore(next)) {
                // in minutes, not a clock time: the server's time zone isn't necessarily the reader's
                long minutes = Math.max(1, (java.time.Duration.between(now, next).getSeconds() + 59) / 60);
                throw new IllegalStateException("An administrator was already reminded about this request. You can remind again in "
                    + minutes + (minutes == 1 ? " minute." : " minutes."));
            }
        }

        jdbcTemplate.update("INSERT INTO request_reminders (kind, record_id, reminded_by, reminded_at) VALUES (?, ?, ?, ?)",
            k, recordId, me.id(), Timestamp.valueOf(now));
        auditLogService.log("REQUEST_REMINDED", "Assets", assetId, "asset",
            "Reminded an administrator about the pending " + k.toLowerCase() + " request for " + propertyNumber);
        // no asset change - "CHANGED" with no data just tells open bells and lists to refresh
        sseEmitterService.emitAsset("CHANGED", assetId, null);
        return Map.of("remindedAt", now, "nextReminderAt", now.plusMinutes(COOLDOWN_MINUTES));
    }

    // Adds how often each request was reminded, and by whom last, to the request list.
    public List<EditRequestView> withReminders(List<EditRequestView> requests) {
        if (requests.isEmpty()) return requests;
        Map<String, EditRequestView.Reminders> byRequest = new HashMap<>();
        jdbcTemplate.query("""
            SELECT r.kind, r.record_id, r.reminded_at, COALESCE(u.full_name, u.username) AS name
            FROM request_reminders r LEFT JOIN users u ON u.user_id = r.reminded_by
            ORDER BY r.reminded_at
            """, rs -> {
            String key = rs.getString("kind") + "-" + rs.getLong("record_id");
            EditRequestView.Reminders prev = byRequest.get(key);
            byRequest.put(key, new EditRequestView.Reminders(
                (prev == null ? 0 : prev.count()) + 1,
                rs.getTimestamp("reminded_at").toLocalDateTime(),
                rs.getString("name")));
        });
        return requests.stream()
            .map(r -> {
                EditRequestView.Reminders rem = byRequest.get(r.kind() + "-" + r.recordId());
                return rem == null ? r : r.withReminders(rem);
            })
            .toList();
    }

    private String roleOf(Long userId) {
        return jdbcTemplate.queryForObject("SELECT `role` FROM users WHERE user_id = ?", String.class, userId);
    }
}
