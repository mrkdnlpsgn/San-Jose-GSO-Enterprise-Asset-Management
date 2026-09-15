package com.sanjose.inventory.repository;

import com.sanjose.inventory.entity.Personnel;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.Optional;

public interface PersonnelRepository extends JpaRepository<Personnel, Long> {
    Optional<Personnel> findByFullName(String fullName);
    boolean existsByFullName(String fullName);
}
