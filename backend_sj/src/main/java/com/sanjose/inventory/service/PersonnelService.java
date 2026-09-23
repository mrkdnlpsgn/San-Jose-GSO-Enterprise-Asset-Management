package com.sanjose.inventory.service;

import com.sanjose.inventory.dto.PersonnelRequest;
import com.sanjose.inventory.entity.Office;
import com.sanjose.inventory.entity.Personnel;
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
        p.setUserId(rs.getObject("userId", Long.class));
        p.setUsername(rs.getString("username"));
        p.setUserRole(rs.getString("userRole"));
        p.setUserActive(rs.getObject("userActive", Boolean.class));
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

    // Personnel records are the accounts (created/removed on the Accounts page). An admin
    // assigns each one's office here — it's the only place an account's office is set,
    // and sp_personnel_update copies it onto the account. The name always follows the account.
    public Personnel update(Long id, PersonnelRequest req) {
        Personnel existing = findById(id);
        if (existing.getUserId() == null) {
            throw new IllegalArgumentException("Only personnel linked to an account can be edited.");
        }
        if (req.getOfficeId() == null || req.getOfficeId() == 0) {
            throw new IllegalArgumentException("Office is required.");
        }
        jdbcTemplate.update("CALL sp_personnel_update(?, ?, ?, ?, ?)",
            id, existing.getFullName(), req.getPosition(),
            req.getOfficeId().intValue(),
            req.getContactInfo());
        Personnel saved = findById(id);
        auditLogService.log("PERSONNEL_UPDATED", "Personnel", id, "personnel",
            "Updated: " + saved.getFullName() + " — office " + (saved.getOffice() != null ? saved.getOffice().getOfficeName() : "none"));
        return saved;
    }
}
