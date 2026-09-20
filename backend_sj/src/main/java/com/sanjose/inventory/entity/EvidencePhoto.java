package com.sanjose.inventory.entity;

import com.fasterxml.jackson.annotation.JsonIgnore;
import jakarta.persistence.*;
import lombok.*;
import java.time.LocalDateTime;

// Evidence photo attached to an inventory record — the same idea as MaintenancePhoto, but for
// the other modules (an asset, a disposal record). `targetType` says which table `targetId`
// points into; there is no FK because the target varies.
@Entity
@Table(name = "evidence_photos", indexes = @Index(name = "idx_evidence_target", columnList = "target_type,target_id"))
@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class EvidencePhoto {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "photo_id")
    private Long id;

    @Column(name = "target_type", nullable = false, length = 20)
    private String targetType; // ASSET | DISPOSAL

    @Column(name = "target_id", nullable = false)
    private Long targetId;

    // Path relative to the upload root, e.g. "assets/<uuid>.jpg" — never the client-supplied name
    @Column(name = "file_path", nullable = false, length = 255)
    private String filePath;

    @Column(name = "original_filename", length = 255)
    private String originalFilename;

    @Column(name = "content_type", length = 100)
    private String contentType;

    @Column(name = "file_size")
    private Long fileSize;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "uploaded_by", columnDefinition = "INT")
    @JsonIgnore
    private User uploadedBy;

    @Column(name = "uploaded_at", nullable = false, updatable = false)
    private LocalDateTime uploadedAt;

    @PrePersist
    protected void onCreate() {
        if (uploadedAt == null) uploadedAt = LocalDateTime.now();
    }
}
