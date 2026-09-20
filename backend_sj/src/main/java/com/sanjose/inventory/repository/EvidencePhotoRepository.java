package com.sanjose.inventory.repository;

import com.sanjose.inventory.entity.EvidencePhoto;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;

public interface EvidencePhotoRepository extends JpaRepository<EvidencePhoto, Long> {
    List<EvidencePhoto> findByTargetTypeAndTargetIdOrderByUploadedAtDesc(String targetType, Long targetId);
}
