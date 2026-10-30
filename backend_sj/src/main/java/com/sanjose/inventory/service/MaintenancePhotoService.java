package com.sanjose.inventory.service;

import com.sanjose.inventory.dto.MaintenancePhotoResponse;
import com.sanjose.inventory.entity.MaintenanceLedger;
import com.sanjose.inventory.entity.MaintenancePhoto;
import com.sanjose.inventory.entity.User;
import com.sanjose.inventory.exception.ResourceNotFoundException;
import com.sanjose.inventory.repository.MaintenanceLedgerRepository;
import com.sanjose.inventory.repository.MaintenancePhotoRepository;
import com.sanjose.inventory.repository.UserRepository;
import jakarta.annotation.PostConstruct;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

@Service
@RequiredArgsConstructor
@Transactional
public class MaintenancePhotoService {

    private static final String SUBDIR = "maintenance";

    private final MaintenancePhotoRepository photoRepository;
    private final MaintenanceLedgerRepository maintenanceRepository;
    private final UserRepository userRepository;
    private final FileStorageService fileStorageService;
    private final AuditLogService auditLogService;
    private final JdbcTemplate jdbcTemplate;

    // Pre-maintenance (the condition before the work) and post-maintenance (the finished work)
    public static final Set<String> STAGES = Set.of("BEFORE", "AFTER");

    // The stage is a plain column kept out of the JPA entity, so a database without it (hosted,
    // where Hibernate DDL is off) gets it here before any photo is read.
    @PostConstruct
    void ensureStageColumn() {
        Integer has = jdbcTemplate.queryForObject("""
            SELECT COUNT(*) FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'maintenance_photos' AND COLUMN_NAME = 'stage'
            """, Integer.class);
        if (has == null || has == 0) {
            jdbcTemplate.execute("ALTER TABLE maintenance_photos ADD COLUMN stage VARCHAR(10) NULL");
        }
        Integer hasItem = jdbcTemplate.queryForObject("""
            SELECT COUNT(*) FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'maintenance_photos' AND COLUMN_NAME = 'item_id'
            """, Integer.class);
        if (hasItem == null || hasItem == 0) {
            jdbcTemplate.execute("ALTER TABLE maintenance_photos ADD COLUMN item_id INT NULL");
        }
    }

    public List<MaintenancePhotoResponse> list(Long maintenanceId) {
        getMaintenance(maintenanceId); // 404 if the record doesn't exist
        Map<Long, String> stages = new HashMap<>();
        Map<Long, Long> items = new HashMap<>();
        jdbcTemplate.query("SELECT photo_id, stage, item_id FROM maintenance_photos WHERE maintenance_id = ?",
            rs -> {
                stages.put(rs.getLong(1), rs.getString(2));
                items.put(rs.getLong(1), rs.getObject(3, Long.class));
            }, maintenanceId);
        return photoRepository.findByMaintenance_IdOrderByUploadedAtDesc(maintenanceId).stream()
            .map(p -> {
                MaintenancePhotoResponse r = MaintenancePhotoResponse.from(p);
                r.setStage(stages.get(p.getId()));
                r.setItemId(items.get(p.getId()));
                return r;
            })
            .toList();
    }

    // stage: BEFORE or AFTER; older app versions send none and the photo stays unsorted.
    // itemId: the part the photo shows (one of the record's parts), or null for the whole record.
    public MaintenancePhotoResponse upload(Long maintenanceId, MultipartFile file, String stage, Long itemId) {
        String st = stage == null || stage.isBlank() ? null : stage.trim().toUpperCase();
        if (st != null && !STAGES.contains(st)) throw new IllegalArgumentException("Choose pre-maintenance or post-maintenance for the photo.");
        MaintenanceLedger maintenance = getMaintenance(maintenanceId);
        String part = null;
        if (itemId != null) {
            if (st == null) throw new IllegalArgumentException("Choose pre-maintenance or post-maintenance for the part's photo.");
            List<Map<String, Object>> found = jdbcTemplate.queryForList(
                "SELECT particular, additional FROM maintenance_items WHERE item_id = ? AND maintenance_id = ? AND kind = 'PART'",
                itemId, maintenanceId);
            if (found.isEmpty()) throw new ResourceNotFoundException("Part not found on this maintenance record. Save the record first.");
            if ("BEFORE".equals(st) && Boolean.TRUE.equals(asBoolean(found.get(0).get("additional")))) {
                throw new IllegalArgumentException("An additional part has no pre-maintenance photo. Add a post-maintenance photo instead.");
            }
            part = (String) found.get(0).get("particular");
        }
        User uploader = currentUser();

        String relativePath = fileStorageService.storeImage(file, SUBDIR);

        MaintenancePhoto photo = MaintenancePhoto.builder()
            .maintenance(maintenance)
            .filePath(relativePath)
            .originalFilename(file.getOriginalFilename())
            .contentType(file.getContentType())
            .fileSize(file.getSize())
            .uploadedBy(uploader)
            .build();
        photo = photoRepository.saveAndFlush(photo);
        if (st != null) jdbcTemplate.update("UPDATE maintenance_photos SET stage = ?, item_id = ? WHERE photo_id = ?", st, itemId, photo.getId());

        String what = "BEFORE".equals(st) ? "Pre-maintenance photo added" : "AFTER".equals(st) ? "Post-maintenance photo added" : "Evidence photo added";
        auditLogService.log("MAINTENANCE_PHOTO_UPLOADED", "Maintenance", maintenanceId, "maintenance",
            what + (part != null ? " (" + part + ")" : "")
                + (maintenance.getAsset() != null ? " for asset: " + maintenance.getAsset().getPropertyNumber() : ""));

        MaintenancePhotoResponse r = MaintenancePhotoResponse.from(photo);
        r.setStage(st);
        r.setItemId(itemId);
        return r;
    }

    // The photos of parts removed from a record go with them.
    public void deleteForItems(List<Long> itemIds) {
        for (Long itemId : itemIds) {
            List<Map<String, Object>> rows = jdbcTemplate.queryForList(
                "SELECT photo_id, file_path FROM maintenance_photos WHERE item_id = ?", itemId);
            for (Map<String, Object> row : rows) {
                fileStorageService.delete((String) row.get("file_path"));
                jdbcTemplate.update("DELETE FROM maintenance_photos WHERE photo_id = ?", row.get("photo_id"));
            }
        }
    }

    private static Boolean asBoolean(Object v) {
        return v instanceof Boolean b ? b : v instanceof Number n ? n.intValue() != 0 : null;
    }

    public void delete(Long maintenanceId, Long photoId) {
        getMaintenance(maintenanceId); // 404 if the record doesn't exist
        MaintenancePhoto photo = photoRepository.findById(photoId)
            .orElseThrow(() -> new ResourceNotFoundException("Photo not found: " + photoId));
        if (!photo.getMaintenance().getId().equals(maintenanceId)) {
            throw new ResourceNotFoundException("Photo not found: " + photoId);
        }

        fileStorageService.delete(photo.getFilePath());
        photoRepository.delete(photo);

        auditLogService.log("MAINTENANCE_PHOTO_DELETED", "Maintenance", maintenanceId, "maintenance",
            "Evidence photo removed");
    }

    private MaintenanceLedger getMaintenance(Long maintenanceId) {
        return maintenanceRepository.findByIdAndIsDeletedFalse(maintenanceId)
            .orElseThrow(() -> new ResourceNotFoundException("Maintenance record not found: " + maintenanceId));
    }

    private User currentUser() {
        String username = SecurityContextHolder.getContext().getAuthentication().getName();
        return userRepository.findByUsernameIgnoreCase(username).orElse(null);
    }
}
