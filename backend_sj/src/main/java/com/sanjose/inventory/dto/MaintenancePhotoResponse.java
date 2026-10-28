package com.sanjose.inventory.dto;

import com.sanjose.inventory.entity.MaintenancePhoto;
import lombok.Data;
import java.time.LocalDateTime;

@Data
public class MaintenancePhotoResponse {
    private Long id;
    private String url;
    private String originalFilename;
    private Long fileSize;
    private String uploadedByName;
    private LocalDateTime uploadedAt;
    // BEFORE (pre-maintenance) or AFTER (post-maintenance); null for photos from before the split
    private String stage;

    public static MaintenancePhotoResponse from(MaintenancePhoto photo) {
        MaintenancePhotoResponse r = new MaintenancePhotoResponse();
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
