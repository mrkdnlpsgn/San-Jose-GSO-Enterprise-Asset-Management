package com.sanjose.inventory.repository;

import com.sanjose.inventory.entity.DeletedMaintenance;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;

public interface DeletedMaintenanceRepository extends JpaRepository<DeletedMaintenance, Long> {
    List<DeletedMaintenance> findAllByOrderByDeletedAtDesc();
}
