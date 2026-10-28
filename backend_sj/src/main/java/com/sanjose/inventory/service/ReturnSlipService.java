package com.sanjose.inventory.service;

import com.sanjose.inventory.config.AppTime;
import com.sanjose.inventory.entity.Asset;
import com.sanjose.inventory.exception.ResourceNotFoundException;
import jakarta.annotation.PostConstruct;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.sql.Date;
import java.sql.Timestamp;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.List;

// The papers made when an asset changes end user (accountable person) on the Transfer Asset page:
// the old end user returns it to the GSO on a Property Return Slip (LGU Form No. 12, "Returned to
// Stock"), and the GSO issues it to the new end user on a new Property Acknowledgement Receipt.
// Both keep a copy of the asset's details as they were that day, so a reprint matches the signed
// paper even after the asset is edited or renumbered later.
@Service
@RequiredArgsConstructor
public class ReturnSlipService {

    private final JdbcTemplate jdbcTemplate;
    private final AccessService accessService;

    public record ReturnSlip(
        Long id, String slipNumber, Long transferId, Long assetId, String purpose, String officeName,
        Long returnedById, String returnedByName, String returnedByPosition, LocalDate returnDate,
        String propertyNumber, String parNumber, String description, String specifications,
        BigDecimal unitValue, LocalDate acquisitionDate, String createdByName, LocalDateTime createdAt
    ) {}

    public record ParIssue(
        Long id, String parNumber, Long assetId, Long transferId, Long returnSlipId,
        Long personnelId, String personnelName, String personnelPosition, String officeName, LocalDate issueDate,
        String propertyNumber, String description, String specifications, BigDecimal unitValue,
        LocalDate acquisitionDate, boolean original, String createdByName, LocalDateTime createdAt
    ) {}

    public record AssetPapers(List<ReturnSlip> returnSlips, List<ParIssue> pars) {}

    // Created here rather than in a migration script, like asset_transfer_requests, so a hosted
    // database gets them on the next deploy.
    @PostConstruct
    void ensureTables() {
        jdbcTemplate.execute("""
            CREATE TABLE IF NOT EXISTS property_return_slips (
              slip_id              INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
              slip_number          VARCHAR(30) NOT NULL,
              transfer_id          INT NULL,
              asset_id             INT NOT NULL,
              purpose              VARCHAR(30) NOT NULL DEFAULT 'RETURNED_TO_STOCK',
              office_name          VARCHAR(150) NULL,
              returned_by_id       INT NULL,
              returned_by_name     VARCHAR(150) NOT NULL,
              returned_by_position VARCHAR(150) NULL,
              return_date          DATE NOT NULL,
              property_number      VARCHAR(100) NOT NULL,
              par_number           VARCHAR(50) NULL,
              description          VARCHAR(500) NULL,
              specifications       TEXT NULL,
              unit_value           DECIMAL(15,2) NULL,
              acquisition_date     DATE NULL,
              created_by           INT NULL,
              created_at           DATETIME NOT NULL,
              UNIQUE KEY uq_prs_number (slip_number),
              KEY idx_prs_asset (asset_id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
            """);
        jdbcTemplate.execute("""
            CREATE TABLE IF NOT EXISTS asset_par_issuances (
              par_id             INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
              par_number         VARCHAR(50) NOT NULL,
              asset_id           INT NOT NULL,
              transfer_id        INT NULL,
              return_slip_id     INT NULL,
              personnel_id       INT NULL,
              personnel_name     VARCHAR(150) NULL,
              personnel_position VARCHAR(150) NULL,
              office_name        VARCHAR(150) NULL,
              issue_date         DATE NULL,
              property_number    VARCHAR(100) NOT NULL,
              description        VARCHAR(500) NULL,
              specifications     TEXT NULL,
              unit_value         DECIMAL(15,2) NULL,
              acquisition_date   DATE NULL,
              is_original        TINYINT(1) NOT NULL DEFAULT 0,
              created_by         INT NULL,
              created_at         DATETIME NOT NULL,
              KEY idx_par_issue_asset (asset_id),
              KEY idx_par_issue_number (par_number)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
            """);
    }

    // A PAR number once issued stays on paper, so it can't be handed out again even after the
    // asset moves on to a newer one.
    public void requireUnusedPar(String parNumber) {
        Integer n = jdbcTemplate.queryForObject(
            "SELECT COUNT(*) FROM asset_par_issuances WHERE par_number = ?", Integer.class, parNumber);
        if (n != null && n > 0) {
            throw new IllegalArgumentException("PAR Number \"" + parNumber + "\" was already issued before. Use a new one.");
        }
    }

    // The old end user hands the asset back to the GSO. `before` is the asset as it was before the transfer.
    public Long recordReturn(Asset before, Long transferId, Long userId) {
        Long personId = before.getAccountablePerson().getId();
        Person person = person(personId);
        LocalDate today = AppTime.today();
        jdbcTemplate.update("""
            INSERT INTO property_return_slips
              (slip_number, transfer_id, asset_id, purpose, office_name, returned_by_id, returned_by_name,
               returned_by_position, return_date, property_number, par_number, description, specifications,
               unit_value, acquisition_date, created_by, created_at)
            VALUES (?, ?, ?, 'RETURNED_TO_STOCK', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, nextSlipNumber(today), transferId, before.getId(),
            before.getOffice() != null ? before.getOffice().getOfficeName() : null,
            personId, person.name(), person.position(), Date.valueOf(today),
            before.getPropertyNumber(), before.getParNumber(), before.getDescription(), before.getSpecifications(),
            before.getUnitValue(), before.getAcquisitionDate() != null ? Date.valueOf(before.getAcquisitionDate()) : null,
            userId, now());
        return jdbcTemplate.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
    }

    // The new end user's PAR. `before` is the asset before the transfer, `after` once it moved
    // (its property number may have changed with the office). The first time an asset is reissued,
    // the PAR it was registered with is kept too, so its PAR history starts at the beginning.
    public Long issuePar(Asset before, Asset after, String parNumber, Long personnelId, Long transferId,
                         Long returnSlipId, Long userId) {
        Integer earlier = jdbcTemplate.queryForObject(
            "SELECT COUNT(*) FROM asset_par_issuances WHERE asset_id = ?", Integer.class, before.getId());
        if ((earlier == null || earlier == 0) && before.getParNumber() != null && !before.getParNumber().isBlank()) {
            Long firstHolder = before.getAccountablePerson() != null ? before.getAccountablePerson().getId() : null;
            insertPar(before, before.getParNumber(), firstHolder, null, null, before.getAcquisitionDate(), true, userId);
        }
        return insertPar(after, parNumber, personnelId, transferId, returnSlipId, AppTime.today(), false, userId);
    }

    private Long insertPar(Asset a, String parNumber, Long personnelId, Long transferId, Long returnSlipId,
                           LocalDate issueDate, boolean original, Long userId) {
        Person person = personnelId != null ? person(personnelId) : new Person(null, null);
        jdbcTemplate.update("""
            INSERT INTO asset_par_issuances
              (par_number, asset_id, transfer_id, return_slip_id, personnel_id, personnel_name, personnel_position,
               office_name, issue_date, property_number, description, specifications, unit_value, acquisition_date,
               is_original, created_by, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, parNumber, a.getId(), transferId, returnSlipId, personnelId, person.name(), person.position(),
            a.getOffice() != null ? a.getOffice().getOfficeName() : null,
            issueDate != null ? Date.valueOf(issueDate) : null,
            a.getPropertyNumber(), a.getDescription(), a.getSpecifications(), a.getUnitValue(),
            a.getAcquisitionDate() != null ? Date.valueOf(a.getAcquisitionDate()) : null,
            original, userId, now());
        return jdbcTemplate.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
    }

    public AssetPapers forAsset(Long assetId) {
        accessService.requireAssetAccess(assetId);
        return new AssetPapers(
            jdbcTemplate.query(SLIP_SQL + " WHERE s.asset_id = ? ORDER BY s.slip_id DESC", SLIP_MAPPER, assetId),
            jdbcTemplate.query(PAR_SQL + " WHERE i.asset_id = ? ORDER BY i.par_id DESC", PAR_MAPPER, assetId));
    }

    public ReturnSlip slip(Long id) {
        List<ReturnSlip> rows = jdbcTemplate.query(SLIP_SQL + " WHERE s.slip_id = ?", SLIP_MAPPER, id);
        if (rows.isEmpty()) throw new ResourceNotFoundException("Property Return Slip not found.");
        accessService.requireAssetAccess(rows.get(0).assetId());
        return rows.get(0);
    }

    public ParIssue par(Long id) {
        List<ParIssue> rows = jdbcTemplate.query(PAR_SQL + " WHERE i.par_id = ?", PAR_MAPPER, id);
        if (rows.isEmpty()) throw new ResourceNotFoundException("PAR not found.");
        accessService.requireAssetAccess(rows.get(0).assetId());
        return rows.get(0);
    }

    // PRS-YYYY-NNNN, counted per year of the return date.
    private String nextSlipNumber(LocalDate day) {
        String prefix = "PRS-" + day.getYear() + "-";
        Integer max = jdbcTemplate.queryForObject(
            "SELECT MAX(CAST(SUBSTRING(slip_number, ?) AS UNSIGNED)) FROM property_return_slips WHERE slip_number LIKE ?",
            Integer.class, prefix.length() + 1, prefix + "%");
        return prefix + String.format("%04d", (max == null ? 0 : max) + 1);
    }

    private record Person(String name, String position) {}

    private Person person(Long personnelId) {
        List<Person> rows = jdbcTemplate.query("SELECT full_name, position FROM personnel WHERE personnel_id = ?",
            (rs, rn) -> new Person(rs.getString(1), rs.getString(2)), personnelId);
        return rows.isEmpty() ? new Person("Unknown", null) : rows.get(0);
    }

    // DATETIME columns hold UTC (see JacksonTimeConfig).
    private static Timestamp now() {
        return Timestamp.valueOf(LocalDateTime.now(ZoneOffset.UTC));
    }

    private static LocalDate date(java.sql.ResultSet rs, String col) throws java.sql.SQLException {
        Date d = rs.getDate(col);
        return d != null ? d.toLocalDate() : null;
    }

    private static final String SLIP_SQL = """
        SELECT s.*, u.full_name AS created_by_name
        FROM property_return_slips s
        LEFT JOIN users u ON u.user_id = s.created_by
        """;

    private static final RowMapper<ReturnSlip> SLIP_MAPPER = (rs, rn) -> new ReturnSlip(
        rs.getLong("slip_id"), rs.getString("slip_number"), rs.getObject("transfer_id", Long.class),
        rs.getLong("asset_id"), rs.getString("purpose"), rs.getString("office_name"),
        rs.getObject("returned_by_id", Long.class), rs.getString("returned_by_name"), rs.getString("returned_by_position"),
        date(rs, "return_date"), rs.getString("property_number"), rs.getString("par_number"),
        rs.getString("description"), rs.getString("specifications"), rs.getBigDecimal("unit_value"),
        date(rs, "acquisition_date"), rs.getString("created_by_name"),
        rs.getTimestamp("created_at").toLocalDateTime());

    private static final String PAR_SQL = """
        SELECT i.*, u.full_name AS created_by_name
        FROM asset_par_issuances i
        LEFT JOIN users u ON u.user_id = i.created_by
        """;

    private static final RowMapper<ParIssue> PAR_MAPPER = (rs, rn) -> new ParIssue(
        rs.getLong("par_id"), rs.getString("par_number"), rs.getLong("asset_id"),
        rs.getObject("transfer_id", Long.class), rs.getObject("return_slip_id", Long.class),
        rs.getObject("personnel_id", Long.class), rs.getString("personnel_name"), rs.getString("personnel_position"),
        rs.getString("office_name"), date(rs, "issue_date"), rs.getString("property_number"),
        rs.getString("description"), rs.getString("specifications"), rs.getBigDecimal("unit_value"),
        date(rs, "acquisition_date"), rs.getBoolean("is_original"), rs.getString("created_by_name"),
        rs.getTimestamp("created_at").toLocalDateTime());
}
