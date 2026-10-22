package com.sanjose.inventory.service;

import com.sanjose.inventory.config.AppTime;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;

import java.io.IOException;
import java.io.Writer;
import java.sql.Timestamp;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.LinkedHashMap;
import java.util.Map;

// Keeps the live audit_logs table small: entries older than the retention period (default one
// year, AUDIT_RETENTION_DAYS) are moved to audit_logs_archive once a day and at startup. Nothing
// is deleted — archived entries stay in the database and admins can export them as CSV from the
// Audit Logs page. The archive table is created here (CREATE TABLE IF NOT EXISTS, like
// asset_transfer_requests) so no migration has to be run on each database.
@Slf4j
@Service
public class AuditLogArchiveService {

    private static final int BATCH = 2000;
    private static final DateTimeFormatter CSV_TIME = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    private final JdbcTemplate jdbcTemplate;
    private final TransactionTemplate tx;
    private final int retentionDays;

    public AuditLogArchiveService(JdbcTemplate jdbcTemplate, TransactionTemplate tx,
                                  @Value("${audit.retention-days:${AUDIT_RETENTION_DAYS:365}}") int retentionDays) {
        this.jdbcTemplate = jdbcTemplate;
        this.tx = tx;
        this.retentionDays = Math.max(30, retentionDays); // never archive the last month
    }

    public int retentionDays() {
        return retentionDays;
    }

    private void ensureTable() {
        // Same columns as audit_logs plus archived_at. log_id keeps the original id (primary key —
        // Aiven requires one). No foreign key to users, so the archive never blocks account changes.
        jdbcTemplate.execute("""
            CREATE TABLE IF NOT EXISTS audit_logs_archive (
              log_id      BIGINT       NOT NULL,
              user_id     INT          NOT NULL,
              action      VARCHAR(100) NOT NULL,
              module      VARCHAR(50)  NOT NULL,
              target_id   BIGINT       NULL,
              target_type VARCHAR(50)  NULL,
              details     TEXT         NULL,
              ip_address  VARCHAR(45)  NULL,
              logged_at   DATETIME     NOT NULL,
              archived_at DATETIME     NOT NULL,
              PRIMARY KEY (log_id),
              KEY idx_ala_logged_at (logged_at)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci""");
    }

    @EventListener(ApplicationReadyEvent.class)
    public void onStartup() {
        try {
            ensureTable();
            archiveOldEntries();
        } catch (Exception e) {
            log.warn("Audit log archiving at startup failed: {}", e.getMessage());
        }
    }

    // 2:30 AM Manila, when nobody is using the system.
    @Scheduled(cron = "0 30 2 * * *", zone = "Asia/Manila")
    public void nightly() {
        try {
            archiveOldEntries();
        } catch (Exception e) {
            log.warn("Nightly audit log archiving failed: {}", e.getMessage());
        }
    }

    /** Moves every entry older than the retention period to the archive. Returns how many moved. */
    public int archiveOldEntries() {
        ensureTable();
        // logged_at is stored in UTC, like every DATETIME here
        Timestamp cutoff = Timestamp.valueOf(LocalDateTime.now(ZoneOffset.UTC).minusDays(retentionDays));
        int total = 0;
        while (true) {
            // copy then delete in one transaction per batch, so an entry is never in both or neither
            Integer moved = tx.execute(status -> {
                int copied = jdbcTemplate.update("""
                    INSERT IGNORE INTO audit_logs_archive
                      (log_id, user_id, action, module, target_id, target_type, details, ip_address, logged_at, archived_at)
                    SELECT log_id, user_id, action, module, target_id, target_type, details, ip_address, logged_at, UTC_TIMESTAMP()
                    FROM audit_logs WHERE logged_at < ? ORDER BY log_id LIMIT ?""", cutoff, BATCH);
                if (copied == 0 && count("SELECT COUNT(*) FROM audit_logs WHERE logged_at < ?", cutoff) == 0) return 0;
                return jdbcTemplate.update("""
                    DELETE a FROM audit_logs a JOIN audit_logs_archive r ON r.log_id = a.log_id
                    WHERE a.logged_at < ?""", cutoff);
            });
            if (moved == null || moved == 0) break;
            total += moved;
        }
        if (total > 0) log.info("Archived {} audit log entries older than {} days", total, retentionDays);
        return total;
    }

    private int count(String sql, Object... args) {
        Integer n = jdbcTemplate.queryForObject(sql, Integer.class, args);
        return n != null ? n : 0;
    }

    /** Sizes and date ranges of the live log and the archive, for the Audit Logs page. */
    public Map<String, Object> summary() {
        ensureTable();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("retentionDays", retentionDays);
        out.put("liveCount", count("SELECT COUNT(*) FROM audit_logs"));
        out.put("archivedCount", count("SELECT COUNT(*) FROM audit_logs_archive"));
        Map<String, Object> range = jdbcTemplate.queryForMap(
            "SELECT MIN(logged_at) AS oldest, MAX(logged_at) AS newest FROM audit_logs_archive");
        out.put("archivedOldest", iso(range.get("oldest")));
        out.put("archivedNewest", iso(range.get("newest")));
        return out;
    }

    // as "…Z" UTC, like every other time the API returns
    private static String iso(Object t) {
        if (t instanceof Timestamp ts) return ts.toLocalDateTime().toString() + "Z";
        if (t instanceof LocalDateTime ldt) return ldt + "Z";
        return null;
    }

    private static String manila(Timestamp utc) {
        if (utc == null) return "";
        return utc.toLocalDateTime().atOffset(ZoneOffset.UTC).atZoneSameInstant(AppTime.ZONE).format(CSV_TIME);
    }

    private static String csv(Object v) {
        String s = v == null ? "" : v.toString();
        // a leading = + - @ would run as a formula in Excel
        if (!s.isEmpty() && "=+-@".indexOf(s.charAt(0)) >= 0) s = "'" + s;
        return "\"" + s.replace("\"", "\"\"") + "\"";
    }

    /**
     * Writes archived entries logged between [from] and [to] (Philippine dates, inclusive; either may be
     * null) as CSV, oldest first. Times in the file are Philippine time.
     */
    public void exportCsv(LocalDate from, LocalDate to, Writer out) throws IOException {
        ensureTable();
        // Philippine calendar days → UTC bounds
        Timestamp start = from == null ? null
            : Timestamp.valueOf(from.atStartOfDay(AppTime.ZONE).withZoneSameInstant(ZoneOffset.UTC).toLocalDateTime());
        Timestamp end = to == null ? null
            : Timestamp.valueOf(to.plusDays(1).atStartOfDay(AppTime.ZONE).withZoneSameInstant(ZoneOffset.UTC).toLocalDateTime());

        out.write('﻿'); // so Excel reads the file as UTF-8
        out.write("Log ID,Date and Time (PH),Action,Module,Target Type,Target ID,Details,Username,Full Name,IP Address,Archived At (PH)\r\n");
        IOException[] failure = new IOException[1];
        jdbcTemplate.query("""
            SELECT r.*, u.username, u.full_name FROM audit_logs_archive r
            LEFT JOIN users u ON u.user_id = r.user_id
            WHERE (? IS NULL OR r.logged_at >= ?) AND (? IS NULL OR r.logged_at < ?)
            ORDER BY r.logged_at, r.log_id""",
            rs -> {
                if (failure[0] != null) return;
                try {
                    out.write(String.join(",",
                        csv(rs.getLong("log_id")),
                        csv(manila(rs.getTimestamp("logged_at"))),
                        csv(rs.getString("action")),
                        csv(rs.getString("module")),
                        csv(rs.getString("target_type")),
                        csv(rs.getObject("target_id")),
                        csv(rs.getString("details")),
                        csv(rs.getString("username")),
                        csv(rs.getString("full_name")),
                        csv(rs.getString("ip_address")),
                        csv(manila(rs.getTimestamp("archived_at")))));
                    out.write("\r\n");
                } catch (IOException e) {
                    failure[0] = e;
                }
            },
            start, start, end, end);
        if (failure[0] != null) throw failure[0];
        out.flush();
    }
}
