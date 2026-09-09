package com.sanjose.inventory.service;

import com.sanjose.inventory.config.SpHelper;
import com.sanjose.inventory.dto.OfficeRequest;
import com.sanjose.inventory.entity.Office;
import com.sanjose.inventory.entity.User;
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
public class OfficeService {

    private final JdbcTemplate jdbcTemplate;
    private final AuditLogService auditLogService;

    private static final RowMapper<Office> OFFICE_MAPPER = (rs, rn) -> {
        Office o = new Office();
        o.setId(rs.getLong("id"));
        o.setOfficeName(rs.getString("officeName"));
        Timestamp ts = rs.getTimestamp("createdAt");
        o.setCreatedAt(ts != null ? ts.toLocalDateTime() : null);
        Long headId = rs.getObject("hu_id", Long.class);
        if (headId != null) {
            User head = new User();
            head.setId(headId);
            head.setUsername(rs.getString("hu_username"));
            head.setFullName(rs.getString("hu_fullName"));
            o.setHeadUser(head);
        }
        return o;
    };

    public List<Office> findAll(String search) {
        if (search != null && !search.isBlank()) {
            return jdbcTemplate.query("CALL sp_offices_search(?)", OFFICE_MAPPER, search.trim());
        }
        return jdbcTemplate.query("CALL sp_offices_get_all()", OFFICE_MAPPER);
    }

    public Office findById(Long id) {
        List<Office> list = jdbcTemplate.query("CALL sp_offices_get_by_id(?)", OFFICE_MAPPER, id);
        if (list.isEmpty()) throw new ResourceNotFoundException("Office not found: " + id);
        return list.get(0);
    }

    public Office create(OfficeRequest req) {
        Long newId = SpHelper.callWithOutLong(jdbcTemplate,
            "CALL sp_offices_create(?, ?, ?)",
            req.getOfficeName(),
            req.getHeadUserId() != null ? req.getHeadUserId().intValue() : 0);
        Office saved = findById(newId);
        auditLogService.log("OFFICE_CREATED", "Offices", newId, "office", "Created: " + saved.getOfficeName());
        return saved;
    }

    public Office update(Long id, OfficeRequest req) {
        findById(id); // throws if not found
        jdbcTemplate.update("CALL sp_offices_update(?, ?, ?)",
            id,
            req.getOfficeName(),
            req.getHeadUserId() != null ? req.getHeadUserId().intValue() : 0);
        Office saved = findById(id);
        auditLogService.log("OFFICE_UPDATED", "Offices", id, "office", "Updated: " + saved.getOfficeName());
        return saved;
    }

    public void delete(Long id) {
        Office office = findById(id);
        // assets.office_id is a NO ACTION FK (unlike users.office_id / asset_history's
        // office columns, which SET NULL) — deleting while assets are still assigned
        // to this office would otherwise fail as a raw SQL constraint error.
        Integer assetCount = jdbcTemplate.queryForObject(
            "SELECT COUNT(*) FROM assets WHERE office_id = ?", Integer.class, id);
        if (assetCount != null && assetCount > 0) {
            throw new ResourceInUseException(
                "Cannot delete \"" + office.getOfficeName() + "\" — " + assetCount +
                " asset(s) are still assigned to it. Reassign or remove those assets first.");
        }
        jdbcTemplate.update("CALL sp_offices_delete(?)", id);
        auditLogService.log("OFFICE_DELETED", "Offices", id, "office", "Deleted: " + office.getOfficeName());
    }
}
