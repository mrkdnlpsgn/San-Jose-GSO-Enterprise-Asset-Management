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
    }

    public List<MaintenancePhotoResponse> list(Long maintenanceId) {
        getMaintenance(maintenanceId); // 404 if the record doesn't exist
        Map<Long, String> stages = new HashMap<>();
        jdbcTemplate.query("SELECT photo_id, stage FROM maintenance_photos WHERE maintenance_id = ? AND stage IS NOT NULL",
            rs -> { stages.put(rs.getLong(1), rs.getString(2)); }, maintenanceId);
        return photoRepository.findByMaintenance_IdOrderByUploadedAtDesc(maintenanceId).stream()
            .map(p -> {
                MaintenancePhotoResponse r = MaintenancePhotoResponse.from(p);
                r.setStage(stages.get(p.getId()));
                return r;
            })
            .toList();
    }

    // stage: BEFORE or AFTER; older app versions send none and the photo stays unsorted
    public MaintenancePhotoResponse upload(Long maintenanceId, MultipartFile file, String stage) {
        String st = stage == null || stage.isBlank() ? null : stage.trim().toUpperCase();
        if (st != null && !STAGES.contains(st)) throw new IllegalArgumentException("Choose pre-maintenance or post-maintenance for the photo.");
        MaintenanceLedger maintenance = getMaintenance(maintenanceId);
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
        if (st != null) jdbcTemplate.update("UPDATE maintenance_photos SET stage = ? WHERE photo_id = ?", st, photo.getId());

        String what = "BEFORE".equals(st) ? "Pre-maintenance photo added" : "AFTER".equals(st) ? "Post-maintenance photo added" : "Evidence photo added";
        auditLogService.log("MAINTENANCE_PHOTO_UPLOADED", "Maintenance", maintenanceId, "maintenance",
            what + (maintenance.getAsset() != null ? " for asset: " + maintenance.getAsset().getPropertyNumber() : ""));

        MaintenancePhotoResponse r = MaintenancePhotoResponse.from(photo);
        r.setStage(st);
        return r;
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
