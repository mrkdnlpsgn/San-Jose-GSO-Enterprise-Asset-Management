package com.sanjose.inventory.repository;

import com.sanjose.inventory.entity.DeletedDisposal;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;

public interface DeletedDisposalRepository extends JpaRepository<DeletedDisposal, Long> {
    List<DeletedDisposal> findAllByOrderByDeletedAtDesc();
}
