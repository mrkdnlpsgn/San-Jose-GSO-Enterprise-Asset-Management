package com.sanjose.inventory.service;

import com.sanjose.inventory.config.SpHelper;
import com.sanjose.inventory.dto.PersonnelRequest;
import com.sanjose.inventory.entity.Office;
import com.sanjose.inventory.entity.Personnel;
import com.sanjose.inventory.exception.ResourceInUseException;
import com.sanjose.inventory.exception.ResourceNotFoundException;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.sql.Timestamp;
import java.util.List;

@Service
@RequiredArgsConstructor
@Transactional
public class PersonnelService {

    private final JdbcTemplate jdbcTemplate;
    private final AuditLogService auditLogService;

    private static final RowMapper<Personnel> PERSONNEL_MAPPER = (rs, rn) -> {
        Personnel p = new Personnel();
        p.setId(rs.getLong("id"));
        p.setFullName(rs.getString("fullName"));
        p.setPosition(rs.getString("position"));
        p.setContactInfo(rs.getString("contactInfo"));
        Timestamp ts = rs.getTimestamp("createdAt");
        p.setCreatedAt(ts != null ? ts.toLocalDateTime() : null);
        Long officeId = rs.getObject("office_id", Long.class);
        if (officeId != null) {
            Office o = new Office();
            o.setId(officeId);
            o.setOfficeName(rs.getString("officeName"));
            p.setOffice(o);
        }
        return p;
    };

    public List<Personnel> findAll(String search) {
        if (search != null && !search.isBlank()) {
            return jdbcTemplate.query("CALL sp_personnel_search(?)", PERSONNEL_MAPPER, search.trim());
        }
        return jdbcTemplate.query("CALL sp_personnel_get_all()", PERSONNEL_MAPPER);
    }

    public Personnel findById(Long id) {
        List<Personnel> list = jdbcTemplate.query("CALL sp_personnel_get_by_id(?)", PERSONNEL_MAPPER, id);
        if (list.isEmpty()) throw new ResourceNotFoundException("Personnel not found: " + id);
        return list.get(0);
    }

    public Personnel create(PersonnelRequest req) {
        Long newId = SpHelper.callWithOutLong(jdbcTemplate,
            "CALL sp_personnel_create(?, ?, ?, ?)",
            req.getFullName(), req.getPosition(),
            req.getOfficeId() != null ? req.getOfficeId().intValue() : 0,
            req.getContactInfo());
        Personnel saved = findById(newId);
        auditLogService.log("PERSONNEL_CREATED", "Personnel", newId, "personnel", "Created: " + saved.getFullName());
        return saved;
    }

    public Personnel update(Long id, PersonnelRequest req) {
        findById(id); // throws if not found
        jdbcTemplate.update("CALL sp_personnel_update(?, ?, ?, ?, ?)",
            id, req.getFullName(), req.getPosition(),
            req.getOfficeId() != null ? req.getOfficeId().intValue() : 0,
            req.getContactInfo());
        Personnel saved = findById(id);
        auditLogService.log("PERSONNEL_UPDATED", "Personnel", id, "personnel", "Updated: " + saved.getFullName());
        return saved;
    }

    public void delete(Long id) {
        Personnel personnel = findById(id);
        // assets.personnel_id and assets.current_user_personnel_id are both NO ACTION
        // FKs (same style as assets.office_id) — deleting while assets still reference
        // this person, either as accountable person or as current user, would otherwise
        // fail as a raw SQL constraint error.
        Integer assetCount = jdbcTemplate.queryForObject(
            "SELECT COUNT(*) FROM assets WHERE personnel_id = ? OR current_user_personnel_id = ?",
            Integer.class, id, id);
        if (assetCount != null && assetCount > 0) {
            throw new ResourceInUseException(
                "Cannot delete \"" + personnel.getFullName() + "\" — " + assetCount +
                " asset(s) still reference them as accountable person or current user. Reassign those assets first.");
        }
        jdbcTemplate.update("CALL sp_personnel_delete(?)", id);
        auditLogService.log("PERSONNEL_DELETED", "Personnel", id, "personnel", "Deleted: " + personnel.getFullName());
    }
}
