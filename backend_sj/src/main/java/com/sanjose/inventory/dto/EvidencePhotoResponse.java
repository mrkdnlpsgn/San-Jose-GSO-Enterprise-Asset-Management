package com.sanjose.inventory.dto;

import com.sanjose.inventory.entity.EvidencePhoto;
import lombok.Data;
import java.time.LocalDateTime;

// Same shape as MaintenancePhotoResponse, so one client component can show either.
@Data
public class EvidencePhotoResponse {
    private Long id;
    private String url;
    private String originalFilename;
    private Long fileSize;
    private String uploadedByName;
    private LocalDateTime uploadedAt;

    public static EvidencePhotoResponse from(EvidencePhoto photo) {
        EvidencePhotoResponse r = new EvidencePhotoResponse();
        r.setId(photo.getId());
        r.setUrl("/uploads/" + photo.getFilePath());
        r.setOriginalFilename(photo.getOriginalFilename());
        r.setFileSize(photo.getFileSize());
        r.setUploadedByName(photo.getUploadedBy() != null
            ? (photo.getUploadedBy().getFullName() != null ? photo.getUploadedBy().getFullName() : photo.getUploadedBy().getUsername())
            : null);
        r.setUploadedAt(photo.getUploadedAt());
        return r;
    }
}
