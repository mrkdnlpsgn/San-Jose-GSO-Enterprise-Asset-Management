package com.sanjose.inventory.service;

import com.sanjose.inventory.config.AppTime;
import com.sanjose.inventory.config.SpHelper;
import com.sanjose.inventory.dto.AssetImportRow;
import com.sanjose.inventory.dto.AssetRequest;
import com.sanjose.inventory.dto.AssetUnitRequest;
import com.sanjose.inventory.entity.Asset;
import com.sanjose.inventory.entity.Category;
import com.sanjose.inventory.entity.Office;
import com.sanjose.inventory.entity.Personnel;
import com.sanjose.inventory.exception.ResourceNotFoundException;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.sql.Date;
import java.sql.Timestamp;
import java.time.LocalDate;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

@Service
@RequiredArgsConstructor
@Transactional
public class AssetService {

    private final JdbcTemplate jdbcTemplate;
    private final AuditLogService auditLogService;
    private final AssetHistoryService assetHistoryService;
    private final SseEmitterService sseEmitterService;
    private final AccessService accessService;
    private final MaintenanceLedgerService maintenanceLedgerService;
    private final DisposalLedgerService disposalLedgerService;
    private final AssetQrService assetQrService;
    private final ArticleService articleService;
    private final PropertyNumberService propertyNumberService;
    private final AssetAddedNotifier assetAddedNotifier;

    // A column a database with older copies of the procedures may not return yet.
    private static Integer optionalInt(java.sql.ResultSet rs, String column) {
        try {
            return rs.getObject(column, Integer.class);
        } catch (java.sql.SQLException e) {
            return null;
        }
    }

    private static final RowMapper<Asset> ASSET_MAPPER = (rs, rn) -> {
        Asset a = new Asset();
        a.setId(rs.getLong("id"));
        a.setPropertyNumber(rs.getString("propertyNumber"));
        a.setParNumber(rs.getString("parNumber"));
        a.setGroupId(rs.getString("groupId"));
        a.setGroupSize(rs.getObject("groupSize", Integer.class));
        a.setGroupTotalValue(rs.getBigDecimal("groupTotalValue"));
        a.setSerialNumber(rs.getString("serialNumber"));
        a.setDescription(rs.getString("description"));
        a.setQuantity(rs.getObject("quantity", Integer.class));
        Date acqDate = rs.getDate("acquisitionDate");
        a.setAcquisitionDate(acqDate != null ? acqDate.toLocalDate() : null);
        a.setUnitValue(rs.getBigDecimal("unitValue"));
        a.setPhysicalCount(rs.getObject("physicalCount", Integer.class));
        a.setShortageOverageQty(rs.getObject("shortageOverageQty", Integer.class));
        a.setShortageOverageValue(rs.getBigDecimal("shortageOverageValue"));
        a.setLocation(rs.getString("location"));
        String cond = rs.getString("condition");
        a.setCondition(cond != null ? Asset.AssetCondition.valueOf(cond) : null);
        String lc = rs.getString("lifecycleStatus");
        a.setLifecycleStatus(lc != null ? Asset.LifecycleStatus.valueOf(lc) : null);
        a.setQrCodePath(rs.getString("qrCodePath"));
        a.setSha256Hash(rs.getString("sha256Hash"));
        a.setQrPayload(AssetQrService.payload(a.getId(), a.getPropertyNumber(), a.getSha256Hash()));
        a.setRemarks(rs.getString("remarks"));
        a.setSpecifications(rs.getString("specifications"));
        Timestamp createdTs = rs.getTimestamp("createdAt");
        a.setCreatedAt(createdTs != null ? createdTs.toLocalDateTime() : null);
        Timestamp updatedTs = rs.getTimestamp("updatedAt");
        a.setUpdatedAt(updatedTs != null ? updatedTs.toLocalDateTime() : null);

        Long catId = rs.getObject("category_id", Long.class);
        if (catId != null) {
            Category c = new Category();
            c.setId(catId);
            c.setCategoryName(rs.getString("categoryName"));
            c.setUsefulLifeYears(optionalInt(rs, "categoryUsefulLifeYears"));
            a.setCategory(c);
        }

        Long officeId = rs.getObject("office_id", Long.class);
        if (officeId != null) {
            Office o = new Office();
            o.setId(officeId);
            o.setOfficeName(rs.getString("officeName"));
            a.setOffice(o);
        }

        Long personnelId = rs.getObject("personnel_id", Long.class);
        if (personnelId != null) {
            Personnel p = new Personnel();
            p.setId(personnelId);
            p.setFullName(rs.getString("personnelName"));
            a.setAccountablePerson(p);
        }

        Long currentUserId = rs.getObject("currentUserId", Long.class);
        if (currentUserId != null) {
            Personnel cu = new Personnel();
            cu.setId(currentUserId);
            cu.setFullName(rs.getString("currentUserName"));
            a.setCurrentUser(cu);
        }

        return a;
    };

    public List<Asset> findAll(String search, int page, int size,
                                Long categoryId, Long officeId, String condition, String lifecycleStatus) {
        List<Asset> assets = jdbcTemplate.query("CALL sp_assets_list(?, ?, ?, ?, ?, ?, ?)", ASSET_MAPPER,
            search, size, page * size, categoryId, officeId, condition, lifecycleStatus);
        articleService.attach(assets);
        return assets;
    }

    public long count(String search, Long categoryId, Long officeId, String condition, String lifecycleStatus) {
        return jdbcTemplate.queryForObject("CALL sp_assets_count(?, ?, ?, ?, ?)", Long.class,
            search, categoryId, officeId, condition, lifecycleStatus);
    }

    public List<Asset> findByGroup(String groupId) {
        List<Asset> assets = jdbcTemplate.query("CALL sp_assets_get_by_group(?)", ASSET_MAPPER, groupId);
        articleService.attach(assets);
        return assets;
    }

    public Asset findById(Long id) {
        List<Asset> list = jdbcTemplate.query("CALL sp_assets_get_by_id(?)", ASSET_MAPPER, id);
        if (list.isEmpty()) throw new ResourceNotFoundException("Asset not found: " + id);
        articleService.attach(list);
        return list.get(0);
    }

    // Registers exactly one asset. Property Number, PAR Number, and Serial Number
    // (when given) must each be unique across every other asset - see resolveDevices.
    public List<Asset> createAll(AssetRequest req) {
        List<Asset> created = createDevices(req);
        assetAddedNotifier.notifyAdded(created);
        return created;
    }

    private List<Asset> createDevices(AssetRequest req) {
        List<AssetRequest> devices = resolveDevices(req, null);
        List<Asset> created = new ArrayList<>();
        for (AssetRequest device : devices) created.add(createOne(device, null));
        return created;
    }

    // Single-result variant for callers that only need the first (a group's lead) asset.
    public Asset create(AssetRequest req) { return createAll(req).get(0); }

    private Asset createOne(AssetRequest req, String groupId) {
        if ("REPAIRABLE".equalsIgnoreCase(req.getCondition())) {
            requireLifeLeftForRepair(req.getCategoryId(), req.getAcquisitionDate(), AppTime.today());
        }
        Long newId = SpHelper.callWithOutLong(jdbcTemplate,
            "CALL sp_assets_create(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            req.getPropertyNumber(), req.getParNumber(), req.getSerialNumber(), req.getDescription(),
            req.getCategoryId(), 1,
            req.getAcquisitionDate(), req.getUnitValue(), req.getOfficeId(),
            req.getPersonnelId(), 1, req.getLocation(),
            req.getCondition(), "ASSIGNED",
            req.getQrCodePath(), null, req.getRemarks(), req.getSpecifications(),
            req.getCurrentUserId(), groupId,
            req.getShortageOverageQty() != null ? req.getShortageOverageQty() : 0,
            req.getShortageOverageValue() != null ? req.getShortageOverageValue() : BigDecimal.ZERO);
        articleService.setOnAsset(newId, req.getArticleId());

        Asset saved = findById(newId);
        // The QR signature needs the new id, so it is issued right after the insert.
        assetQrService.reissue(newId, saved.getPropertyNumber());
        handleConditionLedger(saved);
        ageCondition(newId);

        Long recorderId = getUserIdByUsername(SecurityContextHolder.getContext().getAuthentication().getName());
        assetHistoryService.logEvent(newId, "REGISTERED", null,
            saved.getOffice() != null ? saved.getOffice().getId() : null,
            recorderId, "Asset registered: " + saved.getPropertyNumber());

        auditLogService.log("ASSET_CREATED", "Assets", newId, "asset",
            "Created asset: " + saved.getPropertyNumber());
        Asset result = findById(newId); // re-fetch after potential lifecycle update
        sseEmitterService.emitAsset("CREATED", result.getId(), result);
        return result;
    }

    private static final Set<String> VALID_CONDITIONS = Set.of("NEW", "GOOD", "SERVICEABLE", "REPAIRABLE", "UNSERVICEABLE");

    // Create-only bulk import (spreadsheet → assets). Each row is validated and
    // saved independently - one bad row (unknown category, bad date, etc.) is
    // reported as a failure without aborting the rest of the batch. Runs inside
    // this service's class-level @Transactional, but since every failure is
    // caught here rather than propagated, a partial batch commits normally
    // instead of rolling back the whole import over one bad row.
    public Map<String, Object> bulkImport(List<AssetImportRow> rows) {
        List<Asset> saved = new ArrayList<>();
        List<Map<String, Object>> failed = new ArrayList<>();

        for (AssetImportRow row : rows) {
            try {
                saved.addAll(createDevices(toAssetRequest(row)));
            } catch (Exception e) {
                Map<String, Object> failure = new LinkedHashMap<>();
                failure.put("row", row);
                failure.put("reason", e.getMessage() != null ? e.getMessage() : e.getClass().getSimpleName());
                failed.add(failure);
            }
        }

        // one email per office for the whole import, not one per row
        assetAddedNotifier.notifyAdded(saved);
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("saved", saved);
        result.put("failed", failed);
        return result;
    }

    private AssetRequest toAssetRequest(AssetImportRow row) {
        if (isBlank(row.getDescription())) throw new IllegalArgumentException("Description is required.");
        List<String> parNumbers = isBlank(row.getParNumber()) ? List.of()
            : java.util.Arrays.stream(row.getParNumber().split("[;\\n\\r]+"))
                .map(String::trim).filter(x -> !x.isEmpty()).toList();
        if (parNumbers.isEmpty()) throw new IllegalArgumentException("PAR Number is required.");
        if (parNumbers.size() > 1) throw new IllegalArgumentException(
            "Only one PAR Number is allowed per row. Give each device its own row.");
        if (isBlank(row.getCategoryName())) throw new IllegalArgumentException("Category is required.");
        if (isBlank(row.getOfficeName())) throw new IllegalArgumentException("Location is required.");
        if (isBlank(row.getAccountablePerson())) throw new IllegalArgumentException("Accountable person is required.");
        if (isBlank(row.getPhysicalCount())) throw new IllegalArgumentException("Physical count is required.");
        if (isBlank(row.getAcquisitionDate())) throw new IllegalArgumentException("Acquisition date is required.");
        if (isBlank(row.getUnitValue())) throw new IllegalArgumentException("Unit value is required.");
        if (isBlank(row.getLocation())) throw new IllegalArgumentException("Physical location is required.");
        if (isBlank(row.getCondition())) throw new IllegalArgumentException("Condition is required.");

        String condition = row.getCondition().trim().toUpperCase();
        if (!VALID_CONDITIONS.contains(condition)) {
            throw new IllegalArgumentException(
                "Unknown condition \"" + row.getCondition() + "\". It must be NEW, GOOD, SERVICEABLE, REPAIRABLE, or UNSERVICEABLE.");
        }

        Long categoryId = resolveCategoryId(row.getCategoryName());
        if (categoryId == null) throw new IllegalArgumentException("Unknown category: \"" + row.getCategoryName() + "\"");
        Long articleId = null;
        if (!isBlank(row.getArticle())) {
            articleId = articleService.idByName(categoryId, row.getArticle());
            if (articleId == null) throw new IllegalArgumentException(
                "Unknown article \"" + row.getArticle() + "\" for category \"" + row.getCategoryName() + "\". Add it on the Categories page first.");
        }
        Long officeId = resolveOfficeId(row.getOfficeName());
        if (officeId == null) throw new IllegalArgumentException("Unknown office: \"" + row.getOfficeName() + "\"");
        Long personnelId = resolvePersonnelId(row.getAccountablePerson());
        if (personnelId == null) throw new IllegalArgumentException("Unknown accountable person: \"" + row.getAccountablePerson() + "\"");
        Long currentUserId = null;
        if (!isBlank(row.getCurrentUser())) {
            currentUserId = resolvePersonnelId(row.getCurrentUser());
            if (currentUserId == null) throw new IllegalArgumentException("Unknown current user: \"" + row.getCurrentUser() + "\"");
        }

        AssetRequest req = new AssetRequest();
        int quantity = isBlank(row.getQuantity()) ? 1 : parseInt(row.getQuantity(), "Qty (Property Card)");
        if (quantity != 1) throw new IllegalArgumentException(
            "Qty (Property Card) must be 1. Give each device its own row.");
        // Property Number is left blank so it auto-generates.
        AssetUnitRequest unit = new AssetUnitRequest();
        unit.setParNumber(parNumbers.get(0));
        req.setUnits(List.of(unit));
        req.setDescription(row.getDescription().trim());
        req.setCategoryId(categoryId);
        req.setArticleId(articleId);
        req.setOfficeId(officeId);
        req.setPersonnelId(personnelId);
        req.setCurrentUserId(currentUserId);
        req.setLocation(row.getLocation().trim());
        req.setCondition(condition);
        req.setRemarks(isBlank(row.getRemarks()) ? null : row.getRemarks().trim());
        req.setSpecifications(isBlank(row.getSpecifications()) ? null : row.getSpecifications().trim());

        req.setQuantity(quantity);
        req.setPhysicalCount(parseInt(row.getPhysicalCount(), "Qty (Physical Count)"));
        req.setUnitValue(parseDecimal(row.getUnitValue(), "Unit Value"));

        try {
            req.setAcquisitionDate(LocalDate.parse(row.getAcquisitionDate().trim()));
        } catch (DateTimeParseException e) {
            throw new IllegalArgumentException(
                "Acquisition date \"" + row.getAcquisitionDate() + "\" must be in YYYY-MM-DD format.");
        }

        return req;
    }

    private boolean isBlank(String s) { return s == null || s.isBlank(); }

    // YYYY-MM (acquisition year-month) + ':' + serial the user types by hand,
    // e.g. "2026-07:H78JD80". The prefix must match the acquisition date so a
    // PAR number can't drift from the date it claims to encode.
    private static final Pattern PAR_NUMBER_PATTERN =
        Pattern.compile("^(\\d{4}-(?:0[1-9]|1[0-2])):([A-Za-z0-9-]+)$");

    private String normalizeParNumber(String raw, LocalDate acquisitionDate) {
        if (isBlank(raw)) throw new IllegalArgumentException("PAR Number is required.");
        String par = raw.trim();
        Matcher m = PAR_NUMBER_PATTERN.matcher(par);
        if (!m.matches() || par.length() > 50) {
            throw new IllegalArgumentException(
                "PAR Number \"" + par + "\" must be in YYYY-MM:SERIAL format, e.g. 2026-07:H78JD80.");
        }
        if (acquisitionDate != null) {
            String expected = String.format("%d-%02d", acquisitionDate.getYear(), acquisitionDate.getMonthValue());
            if (!m.group(1).equals(expected)) {
                throw new IllegalArgumentException(
                    "PAR Number \"" + par + "\" must start with the acquisition year-month (" + expected + ").");
            }
        }
        return par;
    }

    // The PAR issued when an asset goes to a new end user (Transfer Asset page): same format and
    // acquisition-month rule as any PAR, and no other asset may hold it.
    public String checkNewParNumber(String raw, Asset asset) {
        if (isBlank(raw)) throw new IllegalArgumentException("Enter the new PAR No. for the new end user.");
        String par = normalizeParNumber(raw, asset.getAcquisitionDate());
        if (par.equalsIgnoreCase(asset.getParNumber() == null ? "" : asset.getParNumber().trim())) {
            throw new IllegalArgumentException("The new PAR No. must differ from the current one (" + par + ").");
        }
        if (existsElsewhere("par_number", par, asset.getId())) {
            throw new IllegalArgumentException(
                "PAR Number \"" + par + "\" is already used by another asset. Each asset needs its own.");
        }
        return par;
    }

    // Turns a create/update request into one fully-resolved AssetRequest for the single
    // device it registers. Qty (Property Card) and Qty (Physical Count) are always 1 -
    // one asset row is always exactly one physical item. Property Number, PAR Number,
    // and (when given) Serial Number are its unique identifiers: each must differ from
    // every other asset, though the same Description/Category can be reused freely
    // (registering another unit of the same model is normal).
    private List<AssetRequest> resolveDevices(AssetRequest req, Asset before) {
        int quantity = req.getQuantity() != null ? req.getQuantity() : 1;
        if (quantity != 1) throw new IllegalArgumentException("Qty (Property Card) is always 1. Register each device as its own asset.");
        if (req.getPhysicalCount() == null || req.getPhysicalCount() != 1) {
            throw new IllegalArgumentException("Qty (Physical Count) is always 1.");
        }

        List<AssetUnitRequest> raw = req.getUnits();
        if (raw == null || raw.isEmpty()) {
            AssetUnitRequest only = new AssetUnitRequest();
            only.setPropertyNumber(req.getPropertyNumber());
            only.setParNumber(req.getParNumber());
            raw = List.of(only);
        }
        if (raw.size() != 1) throw new IllegalArgumentException("Only one device entry is allowed per asset.");

        Long excludeId = before != null ? before.getId() : null;
        AssetUnitRequest in = raw.get(0);
        AssetRequest d = mergeDevice(req, in);
        if (d.getAcquisitionDate() == null) throw new IllegalArgumentException("Acquisition date is required.");
        if (d.getUnitValue() == null) throw new IllegalArgumentException("Unit value is required.");
        if (isBlank(d.getCondition())) throw new IllegalArgumentException("Condition is required.");

        // PAR is required for new assets. Older assets were registered without one, so an edit
        // may leave it blank as long as the asset never had one; a PAR that is given must still
        // be valid and unique.
        boolean keepsNoPar = before != null && isBlank(before.getParNumber()) && isBlank(in.getParNumber());
        String par = keepsNoPar ? null : normalizeParNumber(in.getParNumber(), d.getAcquisitionDate());
        if (par != null && existsElsewhere("par_number", par, excludeId)) {
            throw new IllegalArgumentException(
                "PAR Number \"" + par + "\" is already used by another asset. Each asset needs its own.");
        }
        d.setParNumber(par);

        Long article = req.getArticleId();
        if (article != null && article == 0) {
            article = null;
        } else if (article == null && before != null && before.getArticle() != null
                && before.getCategory() != null && before.getCategory().getId().equals(d.getCategoryId())) {
            article = before.getArticle().getId();
        }
        d.setArticleId(articleService.checkForCategory(article, d.getCategoryId()));

        if (!isBlank(d.getSerialNumber()) && existsElsewhere("serial_number", d.getSerialNumber().trim(), excludeId)) {
            throw new IllegalArgumentException(
                "Serial Number \"" + d.getSerialNumber().trim() + "\" is already used by another asset. Each asset needs its own.");
        }

        String prop = blankToNull(in.getPropertyNumber());
        if (prop == null && before != null) prop = before.getPropertyNumber(); // blank on edit = keep it
        // a move to another office takes that office's code, unless a new number was typed
        if (before != null && Objects.equals(prop, before.getPropertyNumber()) && before.getOffice() != null
                && !Objects.equals(before.getOffice().getId(), d.getOfficeId())) {
            prop = propertyNumberService.withOffice(prop, d.getOfficeId());
        }
        if (prop != null && existsElsewhere("property_number", prop, excludeId)) {
            throw new IllegalArgumentException("Property Number \"" + prop + "\" is already used by another asset.");
        }
        if (prop == null) {
            prop = propertyNumberService.generate(d.getCategoryId(), d.getOfficeId(), d.getAcquisitionDate());
        }
        d.setPropertyNumber(prop);

        return List.of(d);
    }

    // Shared request values, overridden field-by-field by whatever the device entry sets.
    private AssetRequest mergeDevice(AssetRequest shared, AssetUnitRequest u) {
        AssetRequest d = new AssetRequest();
        d.setDescription(shared.getDescription());
        d.setCategoryId(shared.getCategoryId());
        d.setQuantity(1);
        d.setPhysicalCount(1);
        d.setShortageOverageQty(shared.getShortageOverageQty());
        d.setShortageOverageValue(shared.getShortageOverageValue());
        d.setQrCodePath(shared.getQrCodePath());
        d.setLifecycleStatus(shared.getLifecycleStatus());

        d.setSerialNumber(u.getSerialNumber() != null && !u.getSerialNumber().isBlank() ? u.getSerialNumber().trim() : shared.getSerialNumber());
        d.setSpecifications(u.getSpecifications() != null && !u.getSpecifications().isBlank() ? u.getSpecifications().trim() : shared.getSpecifications());
        d.setRemarks(u.getRemarks() != null && !u.getRemarks().isBlank() ? u.getRemarks().trim() : shared.getRemarks());
        d.setUnitValue(u.getUnitValue() != null ? u.getUnitValue() : shared.getUnitValue());
        d.setAcquisitionDate(u.getAcquisitionDate() != null ? u.getAcquisitionDate() : shared.getAcquisitionDate());
        d.setPersonnelId(u.getPersonnelId() != null ? u.getPersonnelId() : shared.getPersonnelId());
        d.setCurrentUserId(u.getCurrentUserId() != null ? u.getCurrentUserId() : shared.getCurrentUserId());
        d.setCondition(!isBlank(u.getCondition()) ? u.getCondition().trim().toUpperCase() : shared.getCondition());

        if (u.getOfficeId() != null) {
            d.setOfficeId(u.getOfficeId());
            // location mirrors the office name; derive it when the device moves office
            d.setLocation(!isBlank(u.getLocation()) ? u.getLocation().trim() : officeName(u.getOfficeId(), shared.getLocation()));
        } else {
            d.setOfficeId(shared.getOfficeId());
            d.setLocation(shared.getLocation());
        }
        return d;
    }

    private String officeName(Long officeId, String fallback) {
        List<String> names = jdbcTemplate.query("SELECT office_name FROM offices WHERE office_id = ?",
            (rs, rn) -> rs.getString(1), officeId);
        return names.isEmpty() ? fallback : names.get(0);
    }

    private String blankToNull(String s) { return isBlank(s) ? null : s.trim(); }

    private Integer parseInt(String raw, String fieldLabel) {
        try {
            return Integer.parseInt(raw.trim());
        } catch (NumberFormatException e) {
            throw new IllegalArgumentException(fieldLabel + " \"" + raw + "\" must be a whole number.");
        }
    }

    private BigDecimal parseDecimal(String raw, String fieldLabel) {
        try {
            return new BigDecimal(raw.trim());
        } catch (NumberFormatException e) {
            throw new IllegalArgumentException(fieldLabel + " \"" + raw + "\" must be a number.");
        }
    }

    // True if `column` (property_number) already belongs to a different asset.
    // Soft-deleted assets keep their row, so they count too.
    private boolean existsElsewhere(String column, String value, Long excludeAssetId) {
        Integer n = jdbcTemplate.queryForObject(
            "SELECT COUNT(*) FROM assets WHERE " + column + " = ? AND (? IS NULL OR asset_id <> ?)",
            Integer.class, value, excludeAssetId, excludeAssetId);
        return n != null && n > 0;
    }

    private Long resolveCategoryId(String name) {
        List<Long> ids = jdbcTemplate.query(
            "SELECT category_id FROM categories WHERE LOWER(category_name) = LOWER(?)",
            (rs, rn) -> rs.getLong(1), name.trim());
        return ids.isEmpty() ? null : ids.get(0);
    }

    private Long resolveOfficeId(String name) {
        List<Long> ids = jdbcTemplate.query(
            "SELECT office_id FROM offices WHERE LOWER(office_name) = LOWER(?)",
            (rs, rn) -> rs.getLong(1), name.trim());
        return ids.isEmpty() ? null : ids.get(0);
    }

    private Long resolvePersonnelId(String name) {
        List<Long> ids = jdbcTemplate.query(
            "SELECT personnel_id FROM personnel WHERE LOWER(full_name) = LOWER(?)",
            (rs, rn) -> rs.getLong(1), name.trim());
        return ids.isEmpty() ? null : ids.get(0);
    }

    // Edits one asset. Any group_id from before this feature was removed is left
    // untouched (so a historical group still displays), but editing never creates,
    // joins, or grows a group.
    public Asset update(Long id, AssetRequest req) {
        Asset before = findById(id);
        // The edit form no longer sends a status: it follows the condition (see
        // handleConditionLedger) and the Transfer page. Blank = keep the current one.
        if (isBlank(req.getLifecycleStatus()) && before.getLifecycleStatus() != null) {
            req.setLifecycleStatus(before.getLifecycleStatus().name());
        }
        List<AssetRequest> devices = resolveDevices(req, before);
        AssetRequest own = devices.get(0);
        updateOne(id, before, own, before.getGroupId());
        return findById(id);
    }

    // Changes only condition/lifecycle status (QR scanner). Deliberately bypasses update()'s
    // full-record validation, which requires a PAR Number and one entry per unit - neither of
    // which older assets have.
    public Asset updateStatus(Long id, String condition, String lifecycleStatus) {
        Asset before = findById(id);
        String cond = parseEnum(Asset.AssetCondition.class, condition, "Condition");
        String life = parseEnum(Asset.LifecycleStatus.class, lifecycleStatus, "Lifecycle status");
        checkConditionChange(before, cond,
            before.getCategory() != null ? before.getCategory().getId() : null, before.getAcquisitionDate());

        jdbcTemplate.update("CALL sp_assets_update_status(?, ?, ?)", id, cond, life);

        Asset saved = findById(id);
        if (before.getCondition() != saved.getCondition()) {
            handleConditionLedger(saved);
        }
        auditLogService.log("ASSET_UPDATED", "Assets", id, "asset",
            "Updated status of " + saved.getPropertyNumber() + ": " + cond + " / " + life);
        Asset result = findById(id); // re-fetch after potential lifecycle update
        sseEmitterService.emitAsset("UPDATED", result.getId(), result);
        return result;
    }

    private <E extends Enum<E>> String parseEnum(Class<E> type, String value, String label) {
        if (isBlank(value)) throw new IllegalArgumentException(label + " is required.");
        try {
            return Enum.valueOf(type, value.trim().toUpperCase()).name();
        } catch (IllegalArgumentException e) {
            throw new IllegalArgumentException(label + " \"" + value + "\" is not valid.");
        }
    }

    private Asset updateOne(Long id, Asset before, AssetRequest req, String groupId) {
        Asset.AssetCondition oldCondition = before.getCondition();
        checkConditionChange(before, req.getCondition(), req.getCategoryId(), req.getAcquisitionDate());
        Long oldOfficeId = before.getOffice() != null ? before.getOffice().getId() : null;
        // A new property number needs a new sticker, so it gets a new QR signature; otherwise the
        // current one is kept. Whatever the client sent is ignored.
        String sha256Hash = before.getSha256Hash() != null && Objects.equals(before.getPropertyNumber(), req.getPropertyNumber())
            ? before.getSha256Hash()
            : assetQrService.issueHash(id, req.getPropertyNumber());

        jdbcTemplate.update("CALL sp_assets_update(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            id,
            req.getPropertyNumber(), req.getParNumber(), req.getSerialNumber(), req.getDescription(),
            req.getCategoryId(), 1,
            req.getAcquisitionDate(), req.getUnitValue(), req.getOfficeId(),
            req.getPersonnelId(), 1, req.getLocation(),
            req.getCondition(), req.getLifecycleStatus(),
            req.getQrCodePath(), sha256Hash, req.getRemarks(), req.getSpecifications(),
            req.getCurrentUserId(), groupId,
            req.getShortageOverageQty() != null ? req.getShortageOverageQty() : 0,
            req.getShortageOverageValue() != null ? req.getShortageOverageValue() : BigDecimal.ZERO);
        articleService.setOnAsset(id, req.getArticleId());

        Asset saved = findById(id);
        if (oldCondition != saved.getCondition()) {
            handleConditionLedger(saved);
        }
        ageCondition(id);

        Long newOfficeId = saved.getOffice() != null ? saved.getOffice().getId() : null;
        if (!java.util.Objects.equals(oldOfficeId, newOfficeId)) {
            Long recorderId = getUserIdByUsername(SecurityContextHolder.getContext().getAuthentication().getName());
            assetHistoryService.logEvent(id, "TRANSFERRED", oldOfficeId, newOfficeId, recorderId,
                "Transferred from " + (before.getOffice() != null ? before.getOffice().getOfficeName() : "unassigned")
                    + " to " + (saved.getOffice() != null ? saved.getOffice().getOfficeName() : "unassigned")
                    // same wording as Transfer Asset notes; the Property Card reads the person from it
                    + (saved.getAccountablePerson() != null && saved.getAccountablePerson().getFullName() != null
                        ? ", accountable: " + saved.getAccountablePerson().getFullName() : ""));
        }

        auditLogService.log("ASSET_UPDATED", "Assets", id, "asset",
            "Updated asset: " + saved.getPropertyNumber());
        Asset result = findById(id); // re-fetch after potential lifecycle update
        sseEmitterService.emitAsset("UPDATED", result.getId(), result);
        return result;
    }

    // A lost or stolen sticker: a new QR signature makes every sticker printed before it fail
    // verification. The asset must then be given a freshly printed sticker.
    public Asset reissueQr(Long id) {
        Asset asset = findById(id);
        assetQrService.reissue(id, asset.getPropertyNumber());
        auditLogService.log("ASSET_QR_REISSUED", "Assets", id, "asset",
            "Reissued QR code for asset: " + asset.getPropertyNumber() + " (older stickers no longer verify)");
        Asset result = findById(id);
        sseEmitterService.emitAsset("UPDATED", result.getId(), result);
        return result;
    }

    public void delete(Long id, String deleteReason) {
        Asset asset = findById(id);
        String username = SecurityContextHolder.getContext().getAuthentication().getName();
        Long deleterId = getUserIdByUsername(username);
        int deleterIdInt = deleterId != null ? deleterId.intValue() : 0;
        // An asset under maintenance/disposal has an active ledger record tied to
        // it - archive that too (not just the asset), so it shows up in its own
        // Recycle Bin section instead of only being reachable via the asset's.
        // No-ops for a serviceable asset, which has no active record to match.
        jdbcTemplate.update("CALL sp_maintenance_soft_delete_by_asset(?, ?, ?, ?)",
            id, deleterIdInt, username, deleteReason);
        jdbcTemplate.update("CALL sp_disposal_soft_delete_by_asset(?, ?, ?, ?)",
            id, deleterIdInt, username, deleteReason);
        jdbcTemplate.update("CALL sp_assets_soft_delete(?, ?, ?, ?)",
            id, deleterIdInt, username, deleteReason);
        auditLogService.log("ASSET_DELETED", "Assets", id, "asset",
            "Deleted: " + asset.getPropertyNumber());
        sseEmitterService.emitAsset("DELETED", id, Map.of("propertyNumber", asset.getPropertyNumber()));
    }

    private void handleConditionLedger(Asset asset) {
        handleConditionLedger(asset, false);
    }

    // bySystem: the change comes from a rule (see applyRepairCostRule), not from the person
    // signed in, so it is carried out even for a staff account instead of becoming a request.
    private void handleConditionLedger(Asset asset, boolean bySystem) {
        if (asset.getCondition() == null) return;
        String username = SecurityContextHolder.getContext().getAuthentication().getName();
        Long recorderId = getUserIdByUsername(username);
        int recId = recorderId != null ? recorderId.intValue() : 0;

        if (!bySystem && !accessService.isAdmin()
                && (asset.getCondition() == Asset.AssetCondition.REPAIRABLE
                    || asset.getCondition() == Asset.AssetCondition.UNSERVICEABLE)) {
            // Staff can't put an asset under maintenance or up for disposal directly -
            // it goes in as a request and the lifecycle moves once an admin approves.
            requestLifecycleChange(asset.getId(),
                asset.getCondition() == Asset.AssetCondition.REPAIRABLE ? "UNDER_MAINTENANCE" : "DISPOSED", null);
            return;
        }

        // Records are never thrown away on a condition change: they are the asset's repair and
        // disposal history (Maintenance/Disposal pages, the asset drawer, the AI's repair count).
        // Open maintenance is closed as COMPLETED with a note; an unfinished disposal that no
        // longer applies is cancelled (soft-deleted with the reason, so it stays traceable);
        // finished and rejected records are left alone.
        if (asset.getCondition() == Asset.AssetCondition.REPAIRABLE) {
            cancelOpenDisposal(asset.getId(), recId, "Cancelled, asset marked repairable");
            // the admin has done what a waiting staff maintenance request asked for
            withdrawPendingRequests("maintenance_ledger", asset.getId(), recId, "an administrator marked the asset repairable");
            if (!hasOpenMaintenance(asset.getId())) {
                SpHelper.callWithOutLong(jdbcTemplate,
                    "CALL sp_maintenance_create(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    asset.getId(), "REPAIR",
                    "Asset flagged as repairable, requires maintenance",
                    "Pending review and assignment",
                    null, AppTime.today(), null, "ONGOING", recId);
            }
            jdbcTemplate.update("CALL sp_assets_update_lifecycle(?, ?)",
                asset.getId(), "UNDER_MAINTENANCE");
            assetHistoryService.logEvent(asset.getId(), "MAINTENANCE", null, null, recorderId,
                "Flagged repairable, maintenance record auto-created");
            sseEmitterService.emitMaintenance("CHANGED", asset.getId(), null);
            sseEmitterService.emitDisposal("CHANGED", asset.getId(), null);

        } else if (asset.getCondition() == Asset.AssetCondition.UNSERVICEABLE) {
            closeOpenMaintenance(asset.getId(), recId, "Closed, asset found unserviceable and sent for disposal");
            withdrawPendingRequests("disposal_ledger", asset.getId(), recId, "an administrator marked the asset unserviceable");
            if (!hasOpenDisposal(asset.getId())) {
                SpHelper.callWithOutLong(jdbcTemplate,
                    "CALL sp_disposal_create(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    asset.getId(),
                    "Asset is unserviceable and flagged for disposal",
                    "Auto-generated from asset condition change",
                    "SALE", "PENDING",
                    AppTime.today(), null, recId,
                    null, null, null);
            }
            jdbcTemplate.update("CALL sp_assets_update_lifecycle(?, ?)",
                asset.getId(), "DISPOSED");
            assetHistoryService.logEvent(asset.getId(), "DISPOSAL", null, null, recorderId,
                "Flagged unserviceable, disposal record auto-created");
            sseEmitterService.emitMaintenance("CHANGED", asset.getId(), null);
            sseEmitterService.emitDisposal("CHANGED", asset.getId(), null);

        } else if (asset.getCondition() == Asset.AssetCondition.SERVICEABLE
                || asset.getCondition() == Asset.AssetCondition.GOOD
                || asset.getCondition() == Asset.AssetCondition.NEW) {
            boolean repaired = closeOpenMaintenance(asset.getId(), recId, "Closed, asset back in service");
            cancelOpenDisposal(asset.getId(), recId, "Cancelled, asset marked serviceable");
            jdbcTemplate.update("CALL sp_assets_update_lifecycle(?, ?)",
                asset.getId(), "ASSIGNED");
            if (repaired) {
                assetHistoryService.logEvent(asset.getId(), "MAINTENANCE", null, null, recorderId,
                    "Repair finished, asset back in service, maintenance record closed");
            }
            sseEmitterService.emitMaintenance("CHANGED", asset.getId(), null);
            sseEmitterService.emitDisposal("CHANGED", asset.getId(), null);
        }
    }

    // ── Condition by age and repair cost ──────────────────────────────────────
    // A working asset is NEW when it enters the inventory, GOOD once it has been in service
    // GOOD_AFTER_YEARS, and SERVICEABLE after SERVICEABLE_AFTER_YEARS. Time in service counts
    // from the acquisition date (the date the asset was added, when it has none). REPAIRABLE and
    // UNSERVICEABLE assets are left alone, and an asset never moves back to a younger condition.
    public static final int GOOD_AFTER_YEARS = 3;
    public static final int SERVICEABLE_AFTER_YEARS = 5;
    public static final String FULLY_DEPRECIATED_REASON = "Fully Depreciated/Ready for Complete Disposal";

    private static final String AGE_SQL =
        "SELECT asset_id, `condition`, TIMESTAMPDIFF(YEAR, COALESCE(acquisition_date, DATE(created_at)), ?) AS years "
            + "FROM assets WHERE is_deleted = 0 AND `condition` IN ('NEW', 'GOOD')";

    // Brings every working asset's condition up to its age; returns how many changed.
    public int ageAllConditions() {
        int changed = 0;
        for (Map<String, Object> row : jdbcTemplate.queryForList(AGE_SQL, Date.valueOf(AppTime.today()))) {
            if (applyAge(((Number) row.get("asset_id")).longValue(), (String) row.get("condition"), (Number) row.get("years"))) changed++;
        }
        return changed;
    }

    private void ageCondition(Long assetId) {
        for (Map<String, Object> row : jdbcTemplate.queryForList(AGE_SQL + " AND asset_id = ?", Date.valueOf(AppTime.today()), assetId)) {
            applyAge(assetId, (String) row.get("condition"), (Number) row.get("years"));
        }
    }

    private boolean applyAge(Long assetId, String condition, Number years) {
        if (years == null) return false;
        String target = years.intValue() >= GOOD_AFTER_YEARS ? byAge(years.intValue()) : condition;
        if (target.equals(condition)) return false;
        // a routine step every asset takes, so it isn't written to the asset's history
        jdbcTemplate.update("UPDATE assets SET `condition` = ? WHERE asset_id = ?", target, assetId);
        sseEmitterService.emitAsset("UPDATED", assetId, null);
        return true;
    }

    private static String byAge(int years) {
        return years >= SERVICEABLE_AFTER_YEARS ? "SERVICEABLE" : years >= GOOD_AFTER_YEARS ? "GOOD" : "NEW";
    }

    // A finished repair puts a REPAIRABLE asset back in service once none of its maintenance is
    // still open: it takes the working condition its age gives it (NEW under GOOD_AFTER_YEARS, GOOD
    // under SERVICEABLE_AFTER_YEARS, SERVICEABLE after) and is assigned again. Returns whether it did.
    public boolean returnToService(Long assetId) {
        Asset asset = findById(assetId);
        if (asset.getCondition() != Asset.AssetCondition.REPAIRABLE || hasOpenMaintenance(assetId)) return false;
        Number years = jdbcTemplate.queryForObject(
            "SELECT TIMESTAMPDIFF(YEAR, COALESCE(acquisition_date, DATE(created_at)), ?) FROM assets WHERE asset_id = ?",
            Number.class, Date.valueOf(AppTime.today()), assetId);
        String condition = byAge(years != null ? years.intValue() : 0);
        jdbcTemplate.update("UPDATE assets SET `condition` = ? WHERE asset_id = ?", condition, assetId);
        jdbcTemplate.update("CALL sp_assets_update_lifecycle(?, ?)", assetId, "ASSIGNED");
        Long recorderId = getUserIdByUsername(SecurityContextHolder.getContext().getAuthentication().getName());
        String label = condition.charAt(0) + condition.substring(1).toLowerCase();
        assetHistoryService.logEvent(assetId, "MAINTENANCE", null, null, recorderId,
            "Repair completed, asset back in service as " + label);
        auditLogService.log("ASSET_UPDATED", "Assets", assetId, "asset",
            "Repair completed: " + asset.getPropertyNumber() + " is back in service as " + label);
        Asset result = findById(assetId);
        sseEmitterService.emitAsset("UPDATED", result.getId(), result);
        return true;
    }

    // Repairable means damaged but still within its useful life (its category's useful life,
    // counted from the acquisition date, or the date it was added). Past that, a damaged asset is
    // unserviceable. A category with no useful life set counts as having life left.
    public void requireLifeLeftForRepair(Long categoryId, LocalDate acquired, LocalDate added) {
        if (categoryId == null) return;
        List<Integer> life = jdbcTemplate.queryForList(
            "SELECT useful_life_years FROM categories WHERE category_id = ?", Integer.class, categoryId);
        LocalDate from = acquired != null ? acquired : added;
        if (life.isEmpty() || life.get(0) == null || from == null) return;
        if (!from.plusYears(life.get(0)).isAfter(AppTime.today())) {
            throw new IllegalArgumentException("This asset is past its useful life of " + life.get(0)
                + " years, so it can't be marked Repairable. Mark it Unserviceable instead.");
        }
    }

    public void requireLifeLeftForRepair(Long assetId) {
        Asset asset = findById(assetId);
        if (asset.getCondition() == Asset.AssetCondition.REPAIRABLE) return;
        requireLifeLeftForRepair(asset.getCategory() != null ? asset.getCategory().getId() : null,
            asset.getAcquisitionDate(), asset.getCreatedAt() != null ? asset.getCreatedAt().toLocalDate() : null);
    }

    // Checks a condition change before it is saved. Becoming REPAIRABLE needs useful life left. A
    // REPAIRABLE asset under repair gets back to NEW / GOOD / SERVICEABLE by completing its
    // maintenance record (with the parts' photos and the completion date), not from here.
    private void checkConditionChange(Asset before, String condition, Long categoryId, LocalDate acquired) {
        if (condition == null || condition.isBlank()) return;
        String to = condition.trim().toUpperCase();
        if (to.equals(name(before.getCondition()))) return;
        if ("REPAIRABLE".equals(to)) {
            requireLifeLeftForRepair(categoryId, acquired,
                before.getCreatedAt() != null ? before.getCreatedAt().toLocalDate() : null);
        } else if (before.getCondition() == Asset.AssetCondition.REPAIRABLE
                && Set.of("NEW", "GOOD", "SERVICEABLE").contains(to) && hasOpenMaintenance(before.getId())) {
            throw new IllegalArgumentException("This asset is under repair. Complete its maintenance record "
                + "(photos of the parts and the completion date) to put it back in service.");
        }
    }

    private static String name(Enum<?> e) { return e != null ? e.name() : null; }

    // A repair that costs more than the asset itself isn't worth making. While the asset still
    // has useful life left (its category's useful life, counted from the date it was added to the
    // inventory) it is marked UNSERVICEABLE and goes up for disposal; once that life is used up
    // it moves to the Recovery records as fully depreciated. A category with no useful life set
    // counts as having life left. Returns what was done: "UNSERVICEABLE", "RECOVERY" or null.
    public String applyRepairCostRule(Long assetId, BigDecimal repairCost) {
        if (assetId == null || repairCost == null) return null;
        List<Asset> found = jdbcTemplate.query("CALL sp_assets_get_by_id(?)", ASSET_MAPPER, assetId);
        if (found.isEmpty()) return null;
        Asset asset = found.get(0);
        if (asset.getUnitValue() == null || repairCost.compareTo(asset.getUnitValue()) <= 0) return null;

        LocalDate added = asset.getAcquisitionDate() != null ? asset.getAcquisitionDate()
            : asset.getCreatedAt() != null ? asset.getCreatedAt().toLocalDate() : null;
        Integer life = asset.getCategory() != null ? asset.getCategory().getUsefulLifeYears() : null;
        boolean lifeLeft = life == null || added == null || added.plusYears(life).isAfter(AppTime.today());
        String costs = "repair cost " + repairCost.toPlainString() + " exceeds unit cost " + asset.getUnitValue().toPlainString();

        if (!lifeLeft) {
            delete(assetId, FULLY_DEPRECIATED_REASON);
            return "RECOVERY";
        }
        if (asset.getCondition() == Asset.AssetCondition.UNSERVICEABLE) return null;
        jdbcTemplate.update("UPDATE assets SET `condition` = 'UNSERVICEABLE' WHERE asset_id = ?", assetId);
        handleConditionLedger(findById(assetId), true);
        Long recorderId = getUserIdByUsername(SecurityContextHolder.getContext().getAuthentication().getName());
        assetHistoryService.logEvent(assetId, "MAINTENANCE", null, null, recorderId,
            "Marked unserviceable automatically: " + costs);
        auditLogService.log("ASSET_UPDATED", "Assets", assetId, "asset",
            "Marked unserviceable: " + asset.getPropertyNumber() + ", " + costs);
        Asset result = findById(assetId);
        sseEmitterService.emitAsset("UPDATED", result.getId(), result);
        return "UNSERVICEABLE";
    }

    private boolean hasOpenMaintenance(Long assetId) {
        Integer n = jdbcTemplate.queryForObject(
            "SELECT COUNT(*) FROM maintenance_ledger WHERE asset_id = ? AND is_deleted = 0 AND approval_status = 'APPROVED' AND status <> 'COMPLETED'",
            Integer.class, assetId);
        return n != null && n > 0;
    }

    private boolean hasOpenDisposal(Long assetId) {
        Integer n = jdbcTemplate.queryForObject(
            "SELECT COUNT(*) FROM disposal_ledger WHERE asset_id = ? AND is_deleted = 0 AND approval_status = 'APPROVED' AND disposal_status <> 'COMPLETED'",
            Integer.class, assetId);
        return n != null && n > 0;
    }

    // Marks the asset's open (approved, unfinished) maintenance COMPLETED, adding why to
    // Actions Taken. A waiting staff maintenance request no longer applies and is withdrawn.
    // Returns whether any record was closed.
    private boolean closeOpenMaintenance(Long assetId, int byUserId, String note) {
        int closed = jdbcTemplate.update(
            "UPDATE maintenance_ledger SET status = 'COMPLETED', completed_date = ?, actions_taken = CONCAT(actions_taken, '\\n', ?) "
                + "WHERE asset_id = ? AND is_deleted = 0 AND approval_status = 'APPROVED' AND status <> 'COMPLETED'",
            Date.valueOf(AppTime.today()), note + " (" + AppTime.today() + ")", assetId);
        withdrawPendingRequests("maintenance_ledger", assetId, byUserId, note);
        return closed > 0;
    }

    // An unfinished disposal (and any waiting disposal request) that no longer applies.
    // Completed disposals are history and are never touched.
    private void cancelOpenDisposal(Long assetId, int byUserId, String reason) {
        jdbcTemplate.update(
            "UPDATE disposal_ledger SET is_deleted = 1, deleted_at = NOW(), deleted_by = ?, delete_reason = ? "
                + "WHERE asset_id = ? AND is_deleted = 0 AND approval_status = 'APPROVED' AND disposal_status <> 'COMPLETED'",
            byUserId == 0 ? null : byUserId, reason, assetId);
        withdrawPendingRequests("disposal_ledger", assetId, byUserId, reason);
    }

    private void withdrawPendingRequests(String table, Long assetId, int byUserId, String reason) {
        jdbcTemplate.update(
            "UPDATE " + table + " SET is_deleted = 1, deleted_at = NOW(), deleted_by = ?, delete_reason = ? "
                + "WHERE asset_id = ? AND is_deleted = 0 AND approval_status = 'PENDING_APPROVAL'",
            byUserId == 0 ? null : byUserId, "Request withdrawn: " + reason, assetId);
    }

    // A staff account's change of an asset to UNDER_MAINTENANCE / DISPOSED: files a
    // maintenance or disposal request (PENDING_APPROVAL) instead of changing the asset.
    // requestedCondition (REPAIRABLE / UNSERVICEABLE, or null) is the condition the staff
    // asked for - held on the request too. The admin's approve() then applies both.
    // No-op if one is already waiting.
    public void requestLifecycleChange(Long assetId, String target, String requestedCondition) {
        boolean maintenance = "UNDER_MAINTENANCE".equals(target);
        String table = maintenance ? "maintenance_ledger" : "disposal_ledger";
        if (hasPendingRequest(table, assetId)) return;

        String username = SecurityContextHolder.getContext().getAuthentication().getName();
        Long requesterId = getUserIdByUsername(username);
        int recId = requesterId != null ? requesterId.intValue() : 0;
        Long newId;
        if (maintenance) {
            newId = SpHelper.callWithOutLong(jdbcTemplate,
                "CALL sp_maintenance_create(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                assetId, "CORRECTIVE",
                "Change to Under Maintenance requested by " + username,
                "Awaiting administrator review",
                null, AppTime.today(), null, "SCHEDULED", recId);
            jdbcTemplate.update("UPDATE maintenance_ledger SET approval_status = 'PENDING_APPROVAL', requested_by = ?, requested_condition = ? WHERE maintenance_id = ?",
                requesterId, requestedCondition, newId);
        } else {
            newId = SpHelper.callWithOutLong(jdbcTemplate,
                "CALL sp_disposal_create(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                assetId,
                "Disposal requested by " + username,
                "Requested from the asset's status, awaiting administrator review",
                "OTHERS", "PENDING",
                AppTime.today(), null, recId,
                null, null, null);
            jdbcTemplate.update("UPDATE disposal_ledger SET approval_status = 'PENDING_APPROVAL', requested_by = ?, requested_condition = ? WHERE disposal_id = ?",
                requesterId, requestedCondition, newId);
        }
        Asset asset = findById(assetId);
        auditLogService.log(maintenance ? "MAINTENANCE_REQUESTED" : "DISPOSAL_REQUESTED",
            maintenance ? "Maintenance" : "Disposal", newId, maintenance ? "maintenance" : "disposal",
            (maintenance ? "Maintenance" : "Disposal") + " requested for asset: " + asset.getPropertyNumber());
        if (maintenance) sseEmitterService.emitMaintenance("CREATED", newId, maintenanceLedgerService.findById(newId));
        else sseEmitterService.emitDisposal("CREATED", newId, disposalLedgerService.findById(newId));
    }

    // MAINTENANCE / DISPOSAL when a request for this asset is waiting for an admin, else null.
    public String pendingRequestKind(Long assetId) {
        if (hasPendingRequest("disposal_ledger", assetId)) return "DISPOSAL";
        if (hasPendingRequest("maintenance_ledger", assetId)) return "MAINTENANCE";
        return null;
    }

    private boolean hasPendingRequest(String table, Long assetId) {
        Integer n = jdbcTemplate.queryForObject(
            "SELECT COUNT(*) FROM " + table + " WHERE asset_id = ? AND approval_status = 'PENDING_APPROVAL' AND is_deleted = 0",
            Integer.class, assetId);
        return n != null && n > 0;
    }

    private Long getUserIdByUsername(String username) {
        List<Long> ids = jdbcTemplate.query(
            "CALL sp_users_get_by_username(?)", (rs, rn) -> rs.getLong("id"), username);
        return ids.isEmpty() ? null : ids.get(0);
    }
}
