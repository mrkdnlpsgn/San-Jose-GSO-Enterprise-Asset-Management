package com.sanjose.inventory.service;

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
        a.setLocation(rs.getString("location"));
        String cond = rs.getString("condition");
        a.setCondition(cond != null ? Asset.AssetCondition.valueOf(cond) : null);
        String lc = rs.getString("lifecycleStatus");
        a.setLifecycleStatus(lc != null ? Asset.LifecycleStatus.valueOf(lc) : null);
        a.setQrCodePath(rs.getString("qrCodePath"));
        a.setSha256Hash(rs.getString("sha256Hash"));
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
            c.setUsefulLifeYears(rs.getObject("categoryUsefulLifeYears", Integer.class));
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

        applyDepreciation(a);
        return a;
    };

    private static void applyDepreciation(Asset a) {
        Integer usefulLifeYears = a.getCategory() != null ? a.getCategory().getUsefulLifeYears() : null;
        DepreciationCalculator.Result result = DepreciationCalculator.compute(
            a.getUnitValue(), a.getAcquisitionDate(), usefulLifeYears);
        if (result != null) {
            a.setAccumulatedDepreciation(result.accumulatedDepreciation());
            a.setCarryingAmount(result.carryingAmount());
        }
    }

    public List<Asset> findAll(String search, int page, int size,
                                Long categoryId, Long officeId, String condition, String lifecycleStatus) {
        List<Asset> assets = jdbcTemplate.query("CALL sp_assets_list(?, ?, ?, ?, ?, ?, ?)", ASSET_MAPPER,
            search, size, page * size, categoryId, officeId, condition, lifecycleStatus);
        return assets;
    }

    public long count(String search, Long categoryId, Long officeId, String condition, String lifecycleStatus) {
        return jdbcTemplate.queryForObject("CALL sp_assets_count(?, ?, ?, ?, ?)", Long.class,
            search, categoryId, officeId, condition, lifecycleStatus);
    }

    public List<Asset> findByGroup(String groupId) {
        return jdbcTemplate.query("CALL sp_assets_get_by_group(?)", ASSET_MAPPER, groupId);
    }

    public Asset findById(Long id) {
        List<Asset> list = jdbcTemplate.query("CALL sp_assets_get_by_id(?)", ASSET_MAPPER, id);
        if (list.isEmpty()) throw new ResourceNotFoundException("Asset not found: " + id);
        return list.get(0);
    }

    // Creates one full asset per device. A request for N devices makes N
    // independent asset records (each with its own numbers, people, price, specs,
    // condition, maintenance/disposal lifecycle...) that share a group_id so the
    // UI can present same-model devices together. Returns every created asset.
    public List<Asset> createAll(AssetRequest req) {
        List<AssetRequest> devices = resolveDevices(req, null);
        // Same description + category as devices already registered => same model, so this joins
        // (or starts) their group even when it's added on its own.
        String matched = autoGroupId(req.getCategoryId(), req.getDescription(), null);
        String groupId = matched != null ? matched : (devices.size() > 1 ? java.util.UUID.randomUUID().toString() : null);
        List<Asset> created = new ArrayList<>();
        for (AssetRequest device : devices) created.add(createOne(device, groupId));
        return created;
    }

    // Single-result variant for callers that only need the first (a group's lead) asset.
    public Asset create(AssetRequest req) { return createAll(req).get(0); }

    private Asset createOne(AssetRequest req, String groupId) {
        Long newId = SpHelper.callWithOutLong(jdbcTemplate,
            "CALL sp_assets_create(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            req.getPropertyNumber(), req.getParNumber(), req.getSerialNumber(), req.getDescription(),
            req.getCategoryId(), 1,
            req.getAcquisitionDate(), req.getUnitValue(), req.getOfficeId(),
            req.getPersonnelId(), 1, req.getLocation(),
            req.getCondition(), "ASSIGNED",
            req.getQrCodePath(), req.getSha256Hash(), req.getRemarks(), req.getSpecifications(),
            req.getCurrentUserId(), groupId);

        Asset saved = findById(newId);
        handleConditionLedger(saved);

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

    private static final Set<String> VALID_CONDITIONS = Set.of("SERVICEABLE", "REPAIRABLE", "UNSERVICEABLE");

    // Create-only bulk import (spreadsheet → assets). Each row is validated and
    // saved independently — one bad row (unknown category, bad date, etc.) is
    // reported as a failure without aborting the rest of the batch. Runs inside
    // this service's class-level @Transactional, but since every failure is
    // caught here rather than propagated, a partial batch commits normally
    // instead of rolling back the whole import over one bad row.
    public Map<String, Object> bulkImport(List<AssetImportRow> rows) {
        List<Asset> saved = new ArrayList<>();
        List<Map<String, Object>> failed = new ArrayList<>();

        for (AssetImportRow row : rows) {
            try {
                saved.addAll(createAll(toAssetRequest(row)));
            } catch (Exception e) {
                Map<String, Object> failure = new LinkedHashMap<>();
                failure.put("row", row);
                failure.put("reason", e.getMessage() != null ? e.getMessage() : e.getClass().getSimpleName());
                failed.add(failure);
            }
        }

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
                "Unknown condition \"" + row.getCondition() + "\" — must be SERVICEABLE, REPAIRABLE, or UNSERVICEABLE.");
        }

        Long categoryId = resolveCategoryId(row.getCategoryName());
        if (categoryId == null) throw new IllegalArgumentException("Unknown category: \"" + row.getCategoryName() + "\"");
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
        // One PAR Number per device; Property Numbers are left blank so they auto-generate.
        List<AssetUnitRequest> importUnits = new ArrayList<>();
        for (String par : parNumbers) {
            AssetUnitRequest u = new AssetUnitRequest();
            u.setParNumber(par);
            importUnits.add(u);
        }
        req.setUnits(importUnits);
        req.setDescription(row.getDescription().trim());
        req.setCategoryId(categoryId);
        req.setOfficeId(officeId);
        req.setPersonnelId(personnelId);
        req.setCurrentUserId(currentUserId);
        req.setLocation(row.getLocation().trim());
        req.setCondition(condition);
        req.setRemarks(isBlank(row.getRemarks()) ? null : row.getRemarks().trim());
        req.setSpecifications(isBlank(row.getSpecifications()) ? null : row.getSpecifications().trim());

        req.setQuantity(isBlank(row.getQuantity()) ? parNumbers.size() : parseInt(row.getQuantity(), "Qty (Property Card)"));
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

    private String normalizeParNumber(String raw, LocalDate acquisitionDate, int unitNo) {
        if (isBlank(raw)) throw new IllegalArgumentException("Device " + unitNo + ": PAR Number is required.");
        String par = raw.trim();
        Matcher m = PAR_NUMBER_PATTERN.matcher(par);
        if (!m.matches() || par.length() > 50) {
            throw new IllegalArgumentException(
                "Device " + unitNo + ": PAR Number \"" + par + "\" must be in YYYY-MM:SERIAL format, e.g. 2026-07:H78JD80.");
        }
        if (acquisitionDate != null) {
            String expected = String.format("%d-%02d", acquisitionDate.getYear(), acquisitionDate.getMonthValue());
            if (!m.group(1).equals(expected)) {
                throw new IllegalArgumentException(
                    "Device " + unitNo + ": PAR Number \"" + par + "\" must start with the acquisition year-month (" + expected + ").");
            }
        }
        return par;
    }

    // Turns a create/update request into one fully-resolved AssetRequest per device.
    //
    // Qty (Property Card) N means N devices, and Qty (Physical Count) must equal it.
    // The top-level request fields are the values shared by every device (same model);
    // each entry in `units` may override ANY of them for that one device (its own
    // numbers, people, price, condition, specs...). Property Number and PAR Number are
    // the unique identifiers, so they must differ per device and across all assets.
    //
    // On update, device 1 is the asset being edited; devices 2..N are new assets added
    // to the same group (this is also how an old "quantity 3" record gets split up).
    private List<AssetRequest> resolveDevices(AssetRequest req, Asset before) {
        int quantity = req.getQuantity() != null ? req.getQuantity() : 1;
        if (quantity < 1 || quantity > 500) throw new IllegalArgumentException("Qty (Property Card) must be between 1 and 500.");
        if (req.getPhysicalCount() == null || req.getPhysicalCount() != quantity) {
            throw new IllegalArgumentException(
                "Qty (Physical Count) must equal Qty (Property Card) — each counted device needs its own Property Number and PAR Number.");
        }

        List<AssetUnitRequest> raw = req.getUnits();
        if (raw == null || raw.isEmpty()) {
            if (quantity != 1) {
                throw new IllegalArgumentException(
                    quantity + " devices need " + quantity + " entries — one Property Number and PAR Number per device.");
            }
            AssetUnitRequest only = new AssetUnitRequest();
            only.setPropertyNumber(req.getPropertyNumber());
            only.setParNumber(req.getParNumber());
            raw = List.of(only);
        }
        if (raw.size() != quantity) {
            throw new IllegalArgumentException(
                "Expected " + quantity + " device entries (one Property Number and PAR Number each) but got " + raw.size() + ".");
        }

        // A device inside a group is always exactly one unit — it can't be edited into several.
        if (before != null && before.getGroupId() != null && quantity != 1) {
            throw new IllegalArgumentException("Devices in a group always have Qty (Property Card) and Qty (Physical Count) of 1.");
        }

        Long excludeId = before != null ? before.getId() : null;
        Set<String> seenProps = new java.util.HashSet<>();
        Set<String> seenPars = new java.util.HashSet<>();
        List<AssetRequest> out = new ArrayList<>();

        for (int i = 0; i < raw.size(); i++) {
            AssetUnitRequest in = raw.get(i);
            int no = i + 1;
            AssetRequest d = mergeDevice(req, in);
            // A shared value can be left empty when each device has its own, so check the merged result.
            if (d.getAcquisitionDate() == null) throw new IllegalArgumentException("Device " + no + ": Acquisition date is required.");
            if (d.getUnitValue() == null) throw new IllegalArgumentException("Device " + no + ": Unit value is required.");
            if (isBlank(d.getCondition())) throw new IllegalArgumentException("Device " + no + ": Condition is required.");

            String par = normalizeParNumber(in.getParNumber(), d.getAcquisitionDate(), no);
            if (!seenPars.add(par.toUpperCase())) {
                throw new IllegalArgumentException("Device " + no + ": PAR Number \"" + par + "\" is used twice in this request.");
            }
            // Only device 1 of an update is an existing row; every other device is new.
            Long ownId = (before != null && i == 0) ? excludeId : null;
            if (existsElsewhere("par_number", par, ownId)) {
                throw new IllegalArgumentException("Device " + no + ": PAR Number \"" + par + "\" is already used by another asset.");
            }
            d.setParNumber(par);

            String prop = blankToNull(in.getPropertyNumber());
            if (prop == null && before != null && i == 0) prop = before.getPropertyNumber(); // blank on edit = keep it
            if (prop != null) {
                if (!seenProps.add(prop.toUpperCase())) {
                    throw new IllegalArgumentException("Device " + no + ": Property Number \"" + prop + "\" is used twice in this request.");
                }
                if (existsElsewhere("property_number", prop, ownId)) {
                    throw new IllegalArgumentException("Device " + no + ": Property Number \"" + prop + "\" is already used by another asset.");
                }
            }
            d.setPropertyNumber(prop);
            out.add(d);
        }

        // Fill blank Property Numbers only after every explicit one is known, so an
        // auto-generated number can't collide with one typed further down the list.
        for (AssetRequest d : out) {
            if (d.getPropertyNumber() == null) {
                int year = d.getAcquisitionDate() != null ? d.getAcquisitionDate().getYear() : LocalDate.now().getYear();
                String generated = generatePropertyNumber(year, seenProps);
                seenProps.add(generated.toUpperCase());
                d.setPropertyNumber(generated);
            }
        }
        return out;
    }

    // Shared request values, overridden field-by-field by whatever the device entry sets.
    private AssetRequest mergeDevice(AssetRequest shared, AssetUnitRequest u) {
        AssetRequest d = new AssetRequest();
        d.setDescription(shared.getDescription());
        d.setCategoryId(shared.getCategoryId());
        d.setQuantity(1);
        d.setPhysicalCount(1);
        d.setQrCodePath(shared.getQrCodePath());
        d.setSha256Hash(shared.getSha256Hash());
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

    // True if `column` (property_number or par_number) already belongs to a
    // different asset. Soft-deleted assets keep their row, so they count too.
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

    // Edits one asset. If the request asks for more than one device (Qty > 1), the extra
    // devices are created as new assets in the same group — an old multi-quantity record
    // becomes a real group this way.
    public Asset update(Long id, AssetRequest req) {
        Asset before = findById(id);
        List<AssetRequest> devices = resolveDevices(req, before);
        AssetRequest own = devices.get(0);

        String oldGroup = before.getGroupId();
        String groupId = oldGroup;
        boolean modelChanged =
            !normalizeModel(before.getDescription()).equals(normalizeModel(own.getDescription()))
            || !java.util.Objects.equals(before.getCategory() != null ? before.getCategory().getId() : null, own.getCategoryId());
        if (modelChanged) {
            // A different model belongs with its own kind: leave the old group, join (or start) the new one.
            String matched = autoGroupId(own.getCategoryId(), own.getDescription(), id);
            groupId = matched != null ? matched : (devices.size() > 1 ? java.util.UUID.randomUUID().toString() : null);
        } else if (devices.size() > 1 && groupId == null) {
            String matched = autoGroupId(own.getCategoryId(), own.getDescription(), id);
            groupId = matched != null ? matched : java.util.UUID.randomUUID().toString();
        }

        updateOne(id, before, own, groupId);
        if (oldGroup != null && !java.util.Objects.equals(oldGroup, groupId)) {
            // sp_assets_update keeps the old group when given none, so clear it explicitly
            if (groupId == null) jdbcTemplate.update("UPDATE assets SET group_id = NULL WHERE asset_id = ?", id);
            dissolveIfSingle(oldGroup);
        }
        for (int i = 1; i < devices.size(); i++) createOne(devices.get(i), groupId);
        return findById(id);
    }

    private static String normalizeModel(String s) { return s == null ? "" : s.trim().toLowerCase(); }

    // Finds the group that same-model devices already belong to: assets with the same description
    // (case/space-insensitive) and category. Standalone matches are pulled into it, separate groups
    // of the same model are merged, and a new group is started if none exists yet. Returns null when
    // there is no other device of this model.
    //
    // Only assets that have a PAR Number take part (devices registered the current way) and only
    // single-unit records — older assets without one are left as they are until they're edited,
    // so adding one new device never folds dozens of historical rows into a group.
    private String autoGroupId(Long categoryId, String description, Long excludeAssetId) {
        if (categoryId == null || isBlank(description)) return null;
        List<Map<String, Object>> rows = jdbcTemplate.queryForList(
            "SELECT asset_id, group_id FROM assets"
            + " WHERE is_deleted = FALSE AND quantity = 1 AND par_number IS NOT NULL"
            + " AND category_id = ? AND LOWER(TRIM(description)) = ? AND (? IS NULL OR asset_id <> ?)",
            categoryId, normalizeModel(description), excludeAssetId, excludeAssetId);
        if (rows.isEmpty()) return null;

        String existing = null;
        for (Map<String, Object> r : rows) {
            if (r.get("group_id") != null) { existing = (String) r.get("group_id"); break; }
        }
        final String target = existing != null ? existing : java.util.UUID.randomUUID().toString();

        List<Object> toMove = new ArrayList<>();
        for (Map<String, Object> r : rows) {
            if (!target.equals(r.get("group_id"))) toMove.add(r.get("asset_id"));
        }
        if (!toMove.isEmpty()) {
            String placeholders = String.join(",", java.util.Collections.nCopies(toMove.size(), "?"));
            List<Object> args = new ArrayList<>();
            args.add(target);
            args.addAll(toMove);
            jdbcTemplate.update("UPDATE assets SET group_id = ? WHERE asset_id IN (" + placeholders + ")", args.toArray());
        }
        return target;
    }

    // A group with a single device left is just a normal asset again.
    private void dissolveIfSingle(String groupId) {
        Integer n = jdbcTemplate.queryForObject(
            "SELECT COUNT(*) FROM assets WHERE group_id = ? AND is_deleted = FALSE", Integer.class, groupId);
        if (n != null && n <= 1) jdbcTemplate.update("UPDATE assets SET group_id = NULL WHERE group_id = ?", groupId);
    }

    private Asset updateOne(Long id, Asset before, AssetRequest req, String groupId) {
        Asset.AssetCondition oldCondition = before.getCondition();
        Long oldOfficeId = before.getOffice() != null ? before.getOffice().getId() : null;

        jdbcTemplate.update("CALL sp_assets_update(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            id,
            req.getPropertyNumber(), req.getParNumber(), req.getSerialNumber(), req.getDescription(),
            req.getCategoryId(), 1,
            req.getAcquisitionDate(), req.getUnitValue(), req.getOfficeId(),
            req.getPersonnelId(), 1, req.getLocation(),
            req.getCondition(), req.getLifecycleStatus(),
            req.getQrCodePath(), req.getSha256Hash(), req.getRemarks(), req.getSpecifications(),
            req.getCurrentUserId(), groupId);

        Asset saved = findById(id);
        if (oldCondition != saved.getCondition()) {
            handleConditionLedger(saved);
        }

        Long newOfficeId = saved.getOffice() != null ? saved.getOffice().getId() : null;
        if (!java.util.Objects.equals(oldOfficeId, newOfficeId)) {
            Long recorderId = getUserIdByUsername(SecurityContextHolder.getContext().getAuthentication().getName());
            assetHistoryService.logEvent(id, "TRANSFERRED", oldOfficeId, newOfficeId, recorderId,
                "Transferred from " + (before.getOffice() != null ? before.getOffice().getOfficeName() : "unassigned")
                    + " to " + (saved.getOffice() != null ? saved.getOffice().getOfficeName() : "unassigned"));
        }

        auditLogService.log("ASSET_UPDATED", "Assets", id, "asset",
            "Updated asset: " + saved.getPropertyNumber());
        Asset result = findById(id); // re-fetch after potential lifecycle update
        sseEmitterService.emitAsset("UPDATED", result.getId(), result);
        return result;
    }

    public void delete(Long id, String deleteReason) {
        Asset asset = findById(id);
        String username = SecurityContextHolder.getContext().getAuthentication().getName();
        Long deleterId = getUserIdByUsername(username);
        int deleterIdInt = deleterId != null ? deleterId.intValue() : 0;
        // An asset under maintenance/disposal has an active ledger record tied to
        // it — archive that too (not just the asset), so it shows up in its own
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
        if (asset.getCondition() == null) return;
        String username = SecurityContextHolder.getContext().getAuthentication().getName();
        Long recorderId = getUserIdByUsername(username);
        int recId = recorderId != null ? recorderId.intValue() : 0;

        if (asset.getCondition() == Asset.AssetCondition.REPAIRABLE) {
            jdbcTemplate.update("CALL sp_disposal_delete_by_asset(?)", asset.getId());
            SpHelper.callWithOutLong(jdbcTemplate,
                "CALL sp_maintenance_create(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                asset.getId(), "REPAIR",
                "Asset flagged as repairable — requires maintenance",
                "Pending review and assignment",
                null, LocalDate.now(), null, "ONGOING", recId);
            jdbcTemplate.update("CALL sp_assets_update_lifecycle(?, ?)",
                asset.getId(), "UNDER_MAINTENANCE");
            assetHistoryService.logEvent(asset.getId(), "MAINTENANCE", null, null, recorderId,
                "Flagged repairable, maintenance record auto-created");
            sseEmitterService.emitMaintenance("CHANGED", asset.getId(), null);

        } else if (asset.getCondition() == Asset.AssetCondition.UNSERVICEABLE) {
            jdbcTemplate.update("CALL sp_maintenance_delete_by_asset(?)", asset.getId());
            SpHelper.callWithOutLong(jdbcTemplate,
                "CALL sp_disposal_create(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                asset.getId(),
                "Asset is unserviceable and flagged for disposal",
                "Auto-generated from asset condition change",
                "SALE", "PENDING",
                LocalDate.now(), null, recId,
                null, null, null);
            jdbcTemplate.update("CALL sp_assets_update_lifecycle(?, ?)",
                asset.getId(), "DISPOSED");
            assetHistoryService.logEvent(asset.getId(), "DISPOSAL", null, null, recorderId,
                "Flagged unserviceable, disposal record auto-created");
            sseEmitterService.emitDisposal("CHANGED", asset.getId(), null);

        } else if (asset.getCondition() == Asset.AssetCondition.SERVICEABLE) {
            jdbcTemplate.update("CALL sp_maintenance_delete_by_asset(?)", asset.getId());
            jdbcTemplate.update("CALL sp_disposal_delete_by_asset(?)", asset.getId());
            jdbcTemplate.update("CALL sp_assets_update_lifecycle(?, ?)",
                asset.getId(), "ASSIGNED");
            sseEmitterService.emitMaintenance("CHANGED", asset.getId(), null);
            sseEmitterService.emitDisposal("CHANGED", asset.getId(), null);
        }
    }

    // Next free COA-YYYY-NNN, skipping
    // anything already claimed earlier in the same request (`taken`, upper-cased).
    private String generatePropertyNumber(int year, Set<String> taken) {
        String prefix = "COA-" + year + "-";
        Integer maxSeq = jdbcTemplate.queryForObject(
            "SELECT MAX(CAST(SUBSTRING(property_number, LENGTH(?) + 1) AS UNSIGNED)) FROM assets WHERE property_number LIKE ?",
            Integer.class, prefix, prefix + "%");
        int next = (maxSeq != null ? maxSeq : 0) + 1;
        String candidate = prefix + String.format("%03d", next);
        while (taken.contains(candidate.toUpperCase())) {
            next++;
            candidate = prefix + String.format("%03d", next);
        }
        return candidate;
    }

    private Long getUserIdByUsername(String username) {
        List<Long> ids = jdbcTemplate.query(
            "CALL sp_users_get_by_username(?)", (rs, rn) -> rs.getLong("id"), username);
        return ids.isEmpty() ? null : ids.get(0);
    }
}
