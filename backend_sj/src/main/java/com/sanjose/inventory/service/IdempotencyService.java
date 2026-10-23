package com.sanjose.inventory.service;

import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

// Backs IdempotencyFilter. Plain JdbcTemplate (not a stored proc, unlike the domain
// services) since this is cross-cutting infra, not business data - a generic
// (key, method, path, username) claim table with no domain-specific shape.
@Service
@RequiredArgsConstructor
public class IdempotencyService {

    @Value("${idempotency.ttl-hours:24}")
    private int ttlHours;

    private final JdbcTemplate jdbcTemplate;

    public record CachedResponse(int status, String body) {}

    private record Row(Integer status, String body, LocalDateTime createdAt) {}

    // Present only if a PRIOR request with this key already finished successfully
    // within the TTL window - replay its response instead of reprocessing. Expired
    // rows are deleted here so the key becomes reusable again.
    public Optional<CachedResponse> findCompleted(String key, String method, String path, String username) {
        List<Row> rows = jdbcTemplate.query(
            "SELECT response_status, response_body, created_at FROM idempotency_keys " +
            "WHERE idempotency_key = ? AND request_method = ? AND request_path = ? AND username = ?",
            (rs, rn) -> new Row(
                rs.getObject("response_status", Integer.class),
                rs.getString("response_body"),
                rs.getTimestamp("created_at").toLocalDateTime()),
            key, method, path, username);

        if (rows.isEmpty()) return Optional.empty();
        Row row = rows.get(0);

        if (row.createdAt().isBefore(LocalDateTime.now().minusHours(ttlHours))) {
            jdbcTemplate.update(
                "DELETE FROM idempotency_keys WHERE idempotency_key = ? AND request_method = ? AND request_path = ? AND username = ?",
                key, method, path, username);
            return Optional.empty();
        }

        return row.status() != null ? Optional.of(new CachedResponse(row.status(), row.body())) : Optional.empty();
    }

    // True if this call is now the sole owner of the key and should proceed to execute
    // the request; false if another request already holds it (in progress or done -
    // callers should check findCompleted() first to distinguish "done" from this).
    // Relies on the table's primary key for atomicity under concurrent requests.
    public boolean tryClaim(String key, String method, String path, String username) {
        try {
            jdbcTemplate.update(
                "INSERT INTO idempotency_keys (idempotency_key, request_method, request_path, username) VALUES (?, ?, ?, ?)",
                key, method, path, username);
            return true;
        } catch (DataIntegrityViolationException e) {
            return false;
        }
    }

    // Successful (2xx) responses are cached so a retried request replays the exact
    // same outcome instead of creating a second record. Failed responses release the
    // claim instead - nothing was actually created, so the same key should be usable
    // again immediately once the client fixes and resubmits.
    public void complete(String key, String method, String path, String username, int status, String body) {
        if (status >= 200 && status < 300) {
            jdbcTemplate.update(
                "UPDATE idempotency_keys SET response_status = ?, response_body = ?, completed_at = NOW() " +
                "WHERE idempotency_key = ? AND request_method = ? AND request_path = ? AND username = ?",
                status, body, key, method, path, username);
        } else {
            jdbcTemplate.update(
                "DELETE FROM idempotency_keys WHERE idempotency_key = ? AND request_method = ? AND request_path = ? AND username = ?",
                key, method, path, username);
        }
    }
}
