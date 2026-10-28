package com.sanjose.inventory.service;

import com.sanjose.inventory.entity.Category;
import com.sanjose.inventory.entity.Office;
import jakarta.annotation.PostConstruct;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

// Property numbers: YEAR-CATEGORY CODE-SERIAL-OFFICE CODE, e.g. 2024-05030-012-1011.
// The year is the acquisition year; the category and office codes are set by an admin on the
// Categories and Offices pages; the serial counts up per category and is never reused (deleted
// assets keep theirs). The office code follows the asset when it moves to another office.
@Service
@RequiredArgsConstructor
@Transactional
public class PropertyNumberService {

    private final JdbcTemplate jdbcTemplate;
    private final AssetQrService assetQrService;
    private final AuditLogService auditLogService;
    private final SseEmitterService sseEmitterService;

    // year, category code, serial, office code
    private static final Pattern FORMAT = Pattern.compile("^(\\d{4})-([A-Za-z0-9]+)-(\\d+)-([A-Za-z0-9]+)$");
    private static final String FORMAT_SQL = "^[0-9]{4}-[A-Za-z0-9]+-[0-9]+-[A-Za-z0-9]+$";
    private static final Pattern CODE = Pattern.compile("^[A-Za-z0-9]{1,10}$");

    // Created here rather than in a migration script so a fresh or hosted database
    // (Render/Aiven, where Hibernate DDL is off) gets them on the next deploy.
    @PostConstruct
    void ensureColumns() {
        for (String table : List.of("categories", "offices")) {
            Integer n = jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = 'property_code'",
                Integer.class, table);
            if (n == null || n == 0) {
                jdbcTemplate.execute("ALTER TABLE " + table + " ADD COLUMN property_code VARCHAR(10) NULL");
            }
        }
        seedDefaultCodes();
    }

    // The usual codes, filled in once while no category or office has a code yet (a fresh or
    // hosted database); after that they are an admin's to change on the Categories and Offices pages.
    // Categories: the COA account of the kind of property (1-06-05-030 ICT Equipment -> 05030).
    // Offices: the LGU office codes used in the budget (1011 Office of the Mayor...).
    private static final Map<String, String> DEFAULT_CATEGORY_CODES = Map.of(
        "Appliances", "05990",                  // Other Machinery and Equipment
        "ICT Equipment", "05030",
        "Office Furniture", "07010",            // Furniture and Fixtures
        "Office Equipment", "05020",
        "Motor Vehicle", "06010",
        "Heavy Equipment", "05080",             // Construction and Heavy Equipment
        "Communication Equipment", "05070",
        "Medical Equipment", "05110",
        "Agricultural Equipment", "05040",      // Agricultural and Forestry Equipment
        "Disaster & Rescue Equipment", "05090"  // Disaster Response and Rescue Equipment
    );
    private static final Map<String, String> DEFAULT_OFFICE_CODES = Map.ofEntries(
        Map.entry("Office of the Mayor", "1011"),
        Map.entry("Office of the Vice Mayor", "1016"),
        Map.entry("Sangguniang Bayan Office", "1021"),
        Map.entry("Human Resource Management Office", "1032"),
        Map.entry("Municipal Planning and Development Office", "1041"),
        Map.entry("Civil Registrar's Office", "1051"),
        Map.entry("General Services Office", "1061"),
        Map.entry("Budget Office", "1071"),
        Map.entry("Accounting Office", "1081"),
        Map.entry("Treasury Office", "1091"),
        Map.entry("Assessor's Office", "1101"),
        Map.entry("Information and Communications Technology Office", "1012"),
        Map.entry("Municipal Health Office", "4411"),
        Map.entry("Municipal Social Welfare and Development Office", "7611"),
        Map.entry("Municipal Agriculture Office", "8711"),
        Map.entry("Municipal Engineering Office", "8751"),
        Map.entry("Disaster Risk Reduction and Management Office", "9911")
    );

    private void seedDefaultCodes() {
        Integer any = jdbcTemplate.queryForObject(
            "SELECT (SELECT COUNT(*) FROM categories WHERE property_code IS NOT NULL) + (SELECT COUNT(*) FROM offices WHERE property_code IS NOT NULL)",
            Integer.class);
        if (any != null && any > 0) return;
        DEFAULT_CATEGORY_CODES.forEach((name, code) -> jdbcTemplate.update(
            "UPDATE categories SET property_code = ? WHERE LOWER(category_name) = LOWER(?) AND property_code IS NULL", code, name));
        DEFAULT_OFFICE_CODES.forEach((name, code) -> jdbcTemplate.update(
            "UPDATE offices SET property_code = ? WHERE LOWER(office_name) = LOWER(?) AND property_code IS NULL", code, name));
    }

    // --- codes ---

    public void attachCategoryCodes(List<Category> categories) {
        Map<Long, String> codes = codes("categories", "category_id");
        categories.forEach((c) -> c.setPropertyCode(codes.get(c.getId())));
    }

    public void attachOfficeCodes(List<Office> offices) {
        Map<Long, String> codes = codes("offices", "office_id");
        offices.forEach((o) -> o.setPropertyCode(codes.get(o.getId())));
    }

    private Map<Long, String> codes(String table, String idColumn) {
        Map<Long, String> out = new HashMap<>();
        jdbcTemplate.query("SELECT " + idColumn + ", property_code FROM " + table + " WHERE property_code IS NOT NULL",
            (rs) -> { out.put(rs.getLong(1), rs.getString(2)); });
        return out;
    }

    // null leaves the code as it is (older clients don't send it); blank clears it.
    public void setCategoryCode(Long id, String code) { setCode("categories", "category_id", "category", id, code); }

    public void setOfficeCode(Long id, String code) { setCode("offices", "office_id", "office", id, code); }

    // Checked before the category/office itself is saved, so a bad code saves nothing.
    public void checkCategoryCode(Long id, String code) { checkCode("categories", "category_id", "category", id, code); }

    public void checkOfficeCode(Long id, String code) { checkCode("offices", "office_id", "office", id, code); }

    private void checkCode(String table, String idColumn, String noun, Long id, String code) {
        if (code == null || code.isBlank()) return;
        String c = code.trim();
        if (!CODE.matcher(c).matches()) {
            throw new IllegalArgumentException("The property number code may only use letters and numbers, up to 10 characters.");
        }
        Integer n = jdbcTemplate.queryForObject(
            "SELECT COUNT(*) FROM " + table + " WHERE property_code = ? AND (? IS NULL OR " + idColumn + " <> ?)",
            Integer.class, c, id, id);
        if (n != null && n > 0) throw new IllegalArgumentException("Code \"" + c + "\" is already used by another " + noun + ".");
    }

    private void setCode(String table, String idColumn, String noun, Long id, String code) {
        if (code == null) return;
        checkCode(table, idColumn, noun, id, code);
        jdbcTemplate.update("UPDATE " + table + " SET property_code = ? WHERE " + idColumn + " = ?",
            code.isBlank() ? null : code.trim(), id);
    }

    private String code(String table, String idColumn, Long id) {
        if (id == null) return null;
        List<String> c = jdbcTemplate.queryForList("SELECT property_code FROM " + table + " WHERE " + idColumn + " = ?", String.class, id);
        return c.isEmpty() ? null : c.get(0);
    }

    private String name(String table, String idColumn, String nameColumn, Long id) {
        List<String> c = jdbcTemplate.queryForList("SELECT " + nameColumn + " FROM " + table + " WHERE " + idColumn + " = ?", String.class, id);
        return c.isEmpty() ? "this" : c.get(0);
    }

    // --- numbers ---

    // A new asset's number. Fails with a clear message when a code hasn't been set yet.
    public String generate(Long categoryId, Long officeId, LocalDate acquisitionDate) {
        String cat = code("categories", "category_id", categoryId);
        if (cat == null) throw new IllegalArgumentException("Set a property number code for the \""
            + name("categories", "category_id", "category_name", categoryId) + "\" category on the Categories page first, or type the Property Number.");
        String office = code("offices", "office_id", officeId);
        if (office == null) throw new IllegalArgumentException("Set a property number code for the \""
            + name("offices", "office_id", "office_name", officeId) + "\" office on the Offices page first, or type the Property Number.");
        return format(acquisitionDate, cat, nextSerial(categoryId), office);
    }

    private static String format(LocalDate date, String cat, int serial, String office) {
        LocalDate d = date != null ? date : com.sanjose.inventory.config.AppTime.today();
        return String.format("%d-%s-%03d-%s", d.getYear(), cat, serial, office);
    }

    // Highest serial any asset of the category has had (deleted ones too), plus one.
    private int nextSerial(Long categoryId) {
        Integer max = jdbcTemplate.queryForObject(
            "SELECT MAX(CAST(SUBSTRING_INDEX(SUBSTRING_INDEX(property_number, '-', 3), '-', -1) AS UNSIGNED)) "
                + "FROM assets WHERE category_id = ? AND property_number REGEXP ?",
            Integer.class, categoryId, FORMAT_SQL);
        return (max != null ? max : 0) + 1;
    }

    // The number with the office code swapped for the new office's. Unchanged when the number
    // isn't in this format (typed by hand) or the new office has no code yet.
    public String withOffice(String propertyNumber, Long officeId) {
        if (propertyNumber == null) return null;
        Matcher m = FORMAT.matcher(propertyNumber);
        String office = code("offices", "office_id", officeId);
        if (!m.matches() || office == null) return propertyNumber;
        return m.group(1) + "-" + m.group(2) + "-" + m.group(3) + "-" + office;
    }

    // --- renumbering existing assets ---

    private static final String ACTIVE_ASSETS = """
        SELECT a.asset_id, a.property_number, a.category_id, a.acquisition_date,
               c.category_name, c.property_code AS cat_code, o.office_name, o.property_code AS office_code
        FROM assets a
        JOIN categories c ON c.category_id = a.category_id
        JOIN offices o ON o.office_id = a.office_id
        WHERE a.is_deleted = FALSE
        """;

    private record Row(Long id, String number, Long categoryId, LocalDate acquired,
                       String categoryName, String catCode, String officeName, String officeCode) {
        // already in the format with the current codes
        boolean current() {
            Matcher m = FORMAT.matcher(number == null ? "" : number);
            return catCode != null && officeCode != null && m.matches()
                && m.group(2).equals(catCode) && m.group(4).equals(officeCode);
        }
    }

    private List<Row> activeRows() {
        return jdbcTemplate.query(ACTIVE_ASSETS + " ORDER BY a.category_id, a.acquisition_date, a.asset_id", (rs, rn) -> new Row(
            rs.getLong("asset_id"), rs.getString("property_number"), rs.getLong("category_id"),
            rs.getDate("acquisition_date") != null ? rs.getDate("acquisition_date").toLocalDate() : null,
            rs.getString("category_name"), rs.getString("cat_code"), rs.getString("office_name"), rs.getString("office_code")));
    }

    // What a renumbering would do: how many assets get a new number, and which categories and
    // offices still need a code first (their assets are left as they are).
    public Map<String, Object> status() {
        List<Row> rows = activeRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("toRenumber", rows.stream().filter(r -> !r.current() && r.catCode() != null && r.officeCode() != null).count());
        out.put("alreadyCurrent", rows.stream().filter(Row::current).count());
        out.put("categoriesMissingCode", rows.stream().filter(r -> r.catCode() == null).map(Row::categoryName).distinct().sorted().toList());
        out.put("officesMissingCode", rows.stream().filter(r -> r.officeCode() == null).map(Row::officeName).distinct().sorted().toList());
        out.put("blocked", rows.stream().filter(r -> r.catCode() == null || r.officeCode() == null).count());
        return out;
    }

    // Gives every active asset that isn't already in the format (with today's codes) a new
    // number, serials continuing per category in order of acquisition. Each gets a new QR
    // signature, so stickers printed before no longer verify and must be reprinted.
    public Map<String, Object> renumberAll() {
        List<Row> rows = activeRows();
        Map<Long, Integer> next = new HashMap<>();
        List<String> changes = new ArrayList<>();
        int renumbered = 0;
        for (Row r : rows) {
            if (r.current() || r.catCode() == null || r.officeCode() == null) continue;
            int serial = next.computeIfAbsent(r.categoryId(), this::nextSerial);
            next.put(r.categoryId(), serial + 1);
            String number = format(r.acquired(), r.catCode(), serial, r.officeCode());
            jdbcTemplate.update("UPDATE assets SET property_number = ?, updated_at = UTC_TIMESTAMP() WHERE asset_id = ?", number, r.id());
            assetQrService.reissue(r.id(), number);
            if (changes.size() < 20) changes.add(r.number() + " -> " + number);
            renumbered++;
        }
        if (renumbered > 0) {
            auditLogService.log("ASSETS_RENUMBERED", "Assets", null, "asset",
                "Renumbered " + renumbered + " asset(s) to YEAR-CATEGORY-SERIAL-OFFICE, e.g. " + String.join(", ", changes.subList(0, Math.min(3, changes.size()))));
            sseEmitterService.emitAsset("CHANGED", null, null);
        }
        Map<String, Object> out = status();
        out.put("renumbered", renumbered);
        return out;
    }
}
