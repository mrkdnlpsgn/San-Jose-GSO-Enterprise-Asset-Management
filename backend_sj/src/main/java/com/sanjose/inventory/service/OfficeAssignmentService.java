package com.sanjose.inventory.service;

import jakarta.annotation.PostConstruct;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

// An account (through its personnel record) can be assigned to several offices. The full set
// lives in personnel_offices; personnel.office_id / users.office_id keep the primary one - the
// first chosen - so the stored procedures and older app versions that read a single office keep
// working. Reads union the primary office in, so a record whose office was set elsewhere (e.g.
// the default admin office) is never missing it.
@Service
@RequiredArgsConstructor
public class OfficeAssignmentService {

    public record OfficeRef(Long id, String officeName) {}

    private final JdbcTemplate jdbcTemplate;

    // Created here rather than in a migration script so a fresh or hosted database
    // (Render/Aiven, where Hibernate DDL is off) gets it on the next deploy.
    @PostConstruct
    void ensureTable() {
        jdbcTemplate.execute("""
            CREATE TABLE IF NOT EXISTS personnel_offices (
              personnel_id INT NOT NULL,
              office_id    INT NOT NULL,
              PRIMARY KEY (personnel_id, office_id),
              KEY idx_personnel_offices_office (office_id),
              CONSTRAINT fk_personnel_offices_personnel FOREIGN KEY (personnel_id)
                REFERENCES personnel (personnel_id) ON DELETE CASCADE,
              CONSTRAINT fk_personnel_offices_office FOREIGN KEY (office_id)
                REFERENCES offices (office_id) ON DELETE CASCADE
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
            """);
    }

    private static final String ASSIGNMENTS_SQL = """
        SELECT p.personnel_id, p.user_id, o.office_id, o.office_name
        FROM (SELECT personnel_id, office_id FROM personnel_offices
              UNION SELECT personnel_id, office_id FROM personnel WHERE office_id IS NOT NULL) po
        JOIN personnel p ON p.personnel_id = po.personnel_id
        JOIN offices o ON o.office_id = po.office_id
        """;
    private static final String ORDER = " ORDER BY (o.office_id = p.office_id) DESC, o.office_name";

    // personnel_id -> offices, primary first
    public Map<Long, List<OfficeRef>> byPersonnel() {
        return group(jdbcTemplate.query(ASSIGNMENTS_SQL + ORDER,
            (rs, rn) -> Map.entry(rs.getLong("personnel_id"), ref(rs))));
    }

    // user_id -> offices, primary first
    public Map<Long, List<OfficeRef>> byUser() {
        return group(jdbcTemplate.query(ASSIGNMENTS_SQL + " WHERE p.user_id IS NOT NULL" + ORDER,
            (rs, rn) -> Map.entry(rs.getLong("user_id"), ref(rs))));
    }

    public List<OfficeRef> ofPersonnel(Long personnelId) {
        return jdbcTemplate.query(ASSIGNMENTS_SQL + " WHERE p.personnel_id = ?" + ORDER, (rs, rn) -> ref(rs), personnelId);
    }

    // The account's offices; also counts users.office_id in case its personnel record is missing.
    public List<OfficeRef> ofUser(Long userId) {
        List<OfficeRef> out = new ArrayList<>(
            jdbcTemplate.query(ASSIGNMENTS_SQL + " WHERE p.user_id = ?" + ORDER, (rs, rn) -> ref(rs), userId));
        jdbcTemplate.query("SELECT o.office_id, o.office_name FROM users u JOIN offices o ON o.office_id = u.office_id WHERE u.user_id = ?",
            rs -> {
                OfficeRef r = ref(rs);
                if (out.stream().noneMatch(x -> x.id().equals(r.id()))) out.add(0, r);
            }, userId);
        return out;
    }

    public List<Long> officeIdsOfUser(Long userId) {
        return ofUser(userId).stream().map(OfficeRef::id).toList();
    }

    public boolean personnelInOffice(Long personnelId, Long officeId) {
        return ofPersonnel(personnelId).stream().anyMatch(o -> o.id().equals(officeId));
    }

    // Replaces a personnel record's office set (the primary must already be on personnel.office_id).
    public void replace(Long personnelId, List<Long> officeIds) {
        jdbcTemplate.update("DELETE FROM personnel_offices WHERE personnel_id = ?", personnelId);
        for (Long officeId : officeIds) {
            jdbcTemplate.update("INSERT IGNORE INTO personnel_offices (personnel_id, office_id) VALUES (?, ?)", personnelId, officeId);
        }
    }

    public static String names(List<OfficeRef> offices) {
        if (offices == null || offices.isEmpty()) return null;
        return offices.stream().map(OfficeRef::officeName).collect(Collectors.joining(", "));
    }

    private static OfficeRef ref(java.sql.ResultSet rs) throws java.sql.SQLException {
        return new OfficeRef(rs.getLong("office_id"), rs.getString("office_name"));
    }

    private static Map<Long, List<OfficeRef>> group(List<Map.Entry<Long, OfficeRef>> rows) {
        Map<Long, List<OfficeRef>> out = new LinkedHashMap<>();
        rows.forEach(e -> out.computeIfAbsent(e.getKey(), k -> new ArrayList<>()).add(e.getValue()));
        return out;
    }
}
