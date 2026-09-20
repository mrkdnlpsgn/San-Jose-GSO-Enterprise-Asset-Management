package com.sanjose.inventory.service;

import com.sanjose.inventory.dto.EvidencePhotoResponse;
import com.sanjose.inventory.entity.EvidencePhoto;
import com.sanjose.inventory.entity.User;
import com.sanjose.inventory.exception.ResourceNotFoundException;
import com.sanjose.inventory.repository.EvidencePhotoRepository;
import com.sanjose.inventory.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;

import java.util.List;

// Evidence photos for records other than maintenance (which has its own MaintenancePhotoService):
// an asset, or a disposal record. Files are stored and validated by FileStorageService
// (images only, 10 MB each), served publicly from /uploads/.
@Service
@RequiredArgsConstructor
@Transactional
public class EvidenceService {

    public enum Target {
        ASSET("ASSET", "assets", "Assets", "asset", "Asset",
            "SELECT COUNT(*) FROM assets WHERE asset_id = ? AND is_deleted = 0"),
        DISPOSAL("DISPOSAL", "disposal", "Disposal", "disposal", "Disposal record",
            "SELECT COUNT(*) FROM disposal_ledger WHERE disposal_id = ? AND is_deleted = 0");

        final String type, subdir, auditTable, auditEntity, label, existsSql;

        Target(String type, String subdir, String auditTable, String auditEntity, String label, String existsSql) {
            this.type = type; this.subdir = subdir; this.auditTable = auditTable;
            this.auditEntity = auditEntity; this.label = label; this.existsSql = existsSql;
        }
    }

    private final EvidencePhotoRepository photoRepository;
    private final UserRepository userRepository;
    private final FileStorageService fileStorageService;
    private final AuditLogService auditLogService;
    private final JdbcTemplate jdbcTemplate;

    public List<EvidencePhotoResponse> list(Target target, Long id) {
        requireExists(target, id);
        return photoRepository.findByTargetTypeAndTargetIdOrderByUploadedAtDesc(target.type, id).stream()
            .map(EvidencePhotoResponse::from)
            .toList();
    }

    public EvidencePhotoResponse upload(Target target, Long id, MultipartFile file) {
        requireExists(target, id);
        String relativePath = fileStorageService.storeImage(file, target.subdir);

        EvidencePhoto photo = photoRepository.save(EvidencePhoto.builder()
            .targetType(target.type)
            .targetId(id)
            .filePath(relativePath)
            .originalFilename(file.getOriginalFilename())
            .contentType(file.getContentType())
            .fileSize(file.getSize())
            .uploadedBy(currentUser())
            .build());

        auditLogService.log(target.type + "_EVIDENCE_UPLOADED", target.auditTable, id, target.auditEntity,
            "Evidence photo added");
        return EvidencePhotoResponse.from(photo);
    }

    public void delete(Target target, Long id, Long photoId) {
        requireExists(target, id);
        EvidencePhoto photo = photoRepository.findById(photoId)
            .orElseThrow(() -> new ResourceNotFoundException("Photo not found: " + photoId));
        if (!photo.getTargetType().equals(target.type) || !photo.getTargetId().equals(id)) {
            throw new ResourceNotFoundException("Photo not found: " + photoId);
        }
        fileStorageService.delete(photo.getFilePath());
        photoRepository.delete(photo);
        auditLogService.log(target.type + "_EVIDENCE_DELETED", target.auditTable, id, target.auditEntity,
            "Evidence photo removed");
    }

    // Used when a record is permanently deleted: nothing should be left pointing at it.
    public void deleteAll(Target target, Long id) {
        for (EvidencePhoto photo : photoRepository.findByTargetTypeAndTargetIdOrderByUploadedAtDesc(target.type, id)) {
            fileStorageService.delete(photo.getFilePath());
            photoRepository.delete(photo);
        }
    }

    private void requireExists(Target target, Long id) {
        Integer n = jdbcTemplate.queryForObject(target.existsSql, Integer.class, id);
        if (n == null || n == 0) throw new ResourceNotFoundException(target.label + " not found: " + id);
    }

    private User currentUser() {
        String username = SecurityContextHolder.getContext().getAuthentication().getName();
        return userRepository.findByUsernameIgnoreCase(username).orElse(null);
    }
}
