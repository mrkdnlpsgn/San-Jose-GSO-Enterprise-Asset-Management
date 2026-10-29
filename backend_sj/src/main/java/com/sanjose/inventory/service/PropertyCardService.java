package com.sanjose.inventory.service;

import com.sanjose.inventory.config.AppTime;
import com.sanjose.inventory.exception.ResourceNotFoundException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.sql.Date;
import java.sql.Timestamp;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

// The LGU's Property Card: its receipt and then every transfer (to whom, and to which office).
// Every asset has one (its receipt line, at least), opened from the asset's details; the Reports
// list carries only assets that have been transferred. Built from the asset, its TRANSFERRED
// history events, and completed disposals - nothing extra is stored.
@Service
@Transactional(readOnly = true)
public class PropertyCardService {

    // One line on the card. receiptQty is set only on the first (receipt) line.
    public record Entry(LocalDate date, String reference, String description, Integer receiptQty,
                        String transferTo, String office, int balanceQty, String kind) {}

    public record Card(Long assetId, String propertyNumber, String parNumber, String description,
                       String category, BigDecimal unitValue, LocalDate acquisitionDate,
                       String currentOffice, String currentAccountable, int transferCount,
                       LocalDate lastTransferDate, List<Entry> entries) {}

    // Transfer Asset page notes end with ", accountable: <name>" (optionally ". Reason: ...").
    private static final Pattern ACCOUNTABLE_NOTE = Pattern.compile("accountable: (.+?)(?:\\. Reason:|$)");

    private final JdbcTemplate jdbcTemplate;
    private final AccessService accessService;

    public PropertyCardService(JdbcTemplate jdbcTemplate, AccessService accessService) {
        this.jdbcTemplate = jdbcTemplate;
        this.accessService = accessService;
    }

    private record AssetRow(Long id, String propertyNumber, String parNumber, String description, String category,
                            BigDecimal unitValue, LocalDate acquisitionDate, Long officeId, String officeName,
                            String accountable) {}

    private record TransferRow(Long assetId, LocalDateTime eventDate, String fromOffice, Long toOfficeId,
                               String toOffice, String toPersonFromRequest, String notes) {}

    private record DisposalRow(Long assetId, LocalDate date, String method, String orNumber) {}

    private static final String ASSET_SQL = """
        SELECT a.asset_id, a.property_number, a.par_number, a.description, c.category_name, a.unit_value,
               a.acquisition_date, a.office_id, o.office_name, p.full_name AS accountable
        FROM assets a
        LEFT JOIN categories c ON c.category_id = a.category_id
        LEFT JOIN offices o ON o.office_id = a.office_id
        LEFT JOIN personnel p ON p.personnel_id = a.personnel_id
        WHERE a.is_deleted = 0
        """;
    private static final String TRANSFERRED_ONLY = """
          AND EXISTS (SELECT 1 FROM asset_history h WHERE h.asset_id = a.asset_id
                      AND h.event_type = 'TRANSFERRED' AND h.to_office_id IS NOT NULL)
        """;

    // The Reports list: the cards of transferred assets the current user may see (all of them for
    // an admin, their own offices' for staff).
    public List<Card> list() {
        AccessService.StaffScope scope = accessService.staffScope();
        String sql = ASSET_SQL + TRANSFERRED_ONLY + (scope == null ? "" : " AND " + scope.sql("a"));
        List<AssetRow> assets = jdbcTemplate.query(sql, (rs, rn) -> assetRow(rs),
            scope == null ? new Object[0] : scope.args());
        List<Card> cards = build(assets);
        cards.sort((x, y) -> y.lastTransferDate().compareTo(x.lastTransferDate()));
        return cards;
    }

    public Card forAsset(Long assetId) {
        accessService.requireAssetAccess(assetId);
        List<AssetRow> assets = jdbcTemplate.query(ASSET_SQL + " AND a.asset_id = ?", (rs, rn) -> assetRow(rs), assetId);
        if (assets.isEmpty()) throw new ResourceNotFoundException("Asset not found.");
        return build(assets).get(0);
    }

    private static AssetRow assetRow(java.sql.ResultSet rs) throws java.sql.SQLException {
        Date acquired = rs.getDate("acquisition_date");
        return new AssetRow(rs.getLong("asset_id"), rs.getString("property_number"), rs.getString("par_number"),
            rs.getString("description"), rs.getString("category_name"), rs.getBigDecimal("unit_value"),
            acquired != null ? acquired.toLocalDate() : null, rs.getObject("office_id", Long.class),
            rs.getString("office_name"), rs.getString("accountable"));
    }

    private List<Card> build(List<AssetRow> assets) {
        if (assets.isEmpty()) return new ArrayList<>();
        List<Long> ids = assets.stream().map(AssetRow::id).toList();
        String marks = String.join(", ", Collections.nCopies(ids.size(), "?"));

        // The person comes from the Transfer Asset request applied at the same moment, when there is one.
        Map<Long, List<TransferRow>> transfers = new LinkedHashMap<>();
        jdbcTemplate.query("""
            SELECT h.asset_id, h.event_date, fo.office_name AS from_office, h.to_office_id, tof.office_name AS to_office,
                   h.notes,
                   (SELECT p.full_name FROM asset_transfer_requests t
                    JOIN personnel p ON p.personnel_id = t.to_personnel_id
                    WHERE t.asset_id = h.asset_id AND t.status = 'APPROVED' AND t.to_office_id = h.to_office_id
                      AND ABS(TIMESTAMPDIFF(SECOND, t.reviewed_at, h.event_date)) <= 120
                    ORDER BY ABS(TIMESTAMPDIFF(SECOND, t.reviewed_at, h.event_date)) LIMIT 1) AS to_person
            FROM asset_history h
            LEFT JOIN offices fo ON fo.office_id = h.from_office_id
            LEFT JOIN offices tof ON tof.office_id = h.to_office_id
            WHERE h.event_type = 'TRANSFERRED' AND h.to_office_id IS NOT NULL AND h.asset_id IN (""" + marks + """
            )
            ORDER BY h.asset_id, h.event_date, h.history_id""",
            rs -> {
                Timestamp at = rs.getTimestamp("event_date");
                transfers.computeIfAbsent(rs.getLong("asset_id"), k -> new ArrayList<>()).add(new TransferRow(
                    rs.getLong("asset_id"), at != null ? at.toLocalDateTime() : null, rs.getString("from_office"),
                    rs.getObject("to_office_id", Long.class), rs.getString("to_office"),
                    rs.getString("to_person"), rs.getString("notes")));
            }, ids.toArray());

        Map<Long, DisposalRow> disposals = new LinkedHashMap<>();
        jdbcTemplate.query("""
            SELECT asset_id, inspection_date, recommended_method, or_number FROM disposal_ledger
            WHERE is_deleted = 0 AND disposal_status = 'COMPLETED' AND approval_status = 'APPROVED'
              AND asset_id IN (""" + marks + ") ORDER BY inspection_date",
            rs -> {
                Date d = rs.getDate("inspection_date");
                disposals.put(rs.getLong("asset_id"), new DisposalRow(rs.getLong("asset_id"),
                    d != null ? d.toLocalDate() : null, rs.getString("recommended_method"), rs.getString("or_number")));
            }, ids.toArray());

        List<Card> cards = new ArrayList<>();
        for (AssetRow a : assets) {
            List<TransferRow> moves = transfers.getOrDefault(a.id(), List.of());
            List<Entry> entries = new ArrayList<>();
            String reference = a.parNumber() != null && !a.parNumber().isBlank()
                ? a.propertyNumber() + " / PAR " + a.parNumber() : a.propertyNumber();

            // Receipt: where the asset was before its first transfer. Never transferred, it is
            // still with the office and the person who received it.
            entries.add(new Entry(a.acquisitionDate(), reference, a.description(), 1,
                moves.isEmpty() ? a.accountable() : null,
                moves.isEmpty() ? a.officeName() : moves.get(0).fromOffice(), 1, "RECEIPT"));

            for (int i = 0; i < moves.size(); i++) {
                TransferRow t = moves.get(i);
                boolean last = i == moves.size() - 1;
                String person = t.toPersonFromRequest();
                if (person == null && t.notes() != null) {
                    Matcher m = ACCOUNTABLE_NOTE.matcher(t.notes());
                    if (m.find()) person = m.group(1).trim();
                }
                // The latest move still holds today: the current accountable person received it.
                if (person == null && last && Objects.equals(t.toOfficeId(), a.officeId())) person = a.accountable();
                entries.add(new Entry(manilaDate(t.eventDate()), a.propertyNumber(),
                    "Transferred from " + (t.fromOffice() != null ? t.fromOffice() : "unassigned"),
                    null, person, t.toOffice(), 1, "TRANSFER"));
            }

            DisposalRow d = disposals.get(a.id());
            if (d != null) {
                entries.add(new Entry(d.date(), d.orNumber() != null ? "OR " + d.orNumber() : a.propertyNumber(),
                    "Disposed" + (d.method() != null ? " (" + d.method() + ")" : ""), null, null, null, 0, "DISPOSAL"));
            }

            cards.add(new Card(a.id(), a.propertyNumber(), a.parNumber(), a.description(), a.category(),
                a.unitValue(), a.acquisitionDate(), a.officeName(), a.accountable(), moves.size(),
                moves.isEmpty() ? null : manilaDate(moves.get(moves.size() - 1).eventDate()), entries));
        }
        return cards;
    }

    // History timestamps are stored in UTC; the card shows the Manila calendar date.
    private static LocalDate manilaDate(LocalDateTime utc) {
        return utc == null ? null : utc.atOffset(ZoneOffset.UTC).atZoneSameInstant(AppTime.ZONE).toLocalDate();
    }
}
