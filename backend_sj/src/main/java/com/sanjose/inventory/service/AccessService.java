package com.sanjose.inventory.service;

import com.sanjose.inventory.exception.ForbiddenException;
import com.sanjose.inventory.exception.ResourceNotFoundException;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Service;

import java.util.List;

// Role-based access: ADMIN sees and manages everything. STAFF only see, edit and
// update assets (and their maintenance / disposal records and history) that belong to
// the office an admin assigned them on the Personnel page — a staff account without an
// office sees nothing. Adding assets, deleting records and approving staff requests
// are admin-only (see also SecurityConfig).
@Service
@RequiredArgsConstructor
public class AccessService {

    // matches no office, so a staff account without one gets empty lists
    private static final long NO_OFFICE = -1L;

    private final JdbcTemplate jdbcTemplate;

    public record CurrentUser(Long id, String username, boolean admin, Long officeId) {}

    public CurrentUser current() {
        var auth = SecurityContextHolder.getContext().getAuthentication();
        if (auth == null) throw new ForbiddenException("Not signed in.");
        List<CurrentUser> rows = jdbcTemplate.query(
            "SELECT user_id, username, `role`, office_id FROM users WHERE LOWER(username) = LOWER(?)",
            (rs, rn) -> new CurrentUser(rs.getLong("user_id"), rs.getString("username"),
                "ADMIN".equalsIgnoreCase(rs.getString("role")), rs.getObject("office_id", Long.class)),
            auth.getName());
        if (rows.isEmpty()) throw new ForbiddenException("Account not found.");
        return rows.get(0);
    }

    public boolean isAdmin() {
        return current().admin();
    }

    // Office filter for list queries: null = every office (admin).
    public Long scopeOfficeId() {
        CurrentUser u = current();
        if (u.admin()) return null;
        return u.officeId() != null ? u.officeId() : NO_OFFICE;
    }

    public void requireAdmin(String action) {
        if (!isAdmin()) throw new ForbiddenException("Only an administrator can " + action + ".");
    }

    public void requireAssetAccess(Long assetId) {
        CurrentUser u = current();
        if (u.admin()) return;
        requireOwnOffice(u, officeOf("SELECT office_id FROM assets WHERE asset_id = ?", assetId, "Asset"));
    }

    public void requireMaintenanceAccess(Long maintenanceId) {
        CurrentUser u = current();
        if (u.admin()) return;
        requireOwnOffice(u, officeOf(
            "SELECT a.office_id FROM maintenance_ledger m JOIN assets a ON a.asset_id = m.asset_id WHERE m.maintenance_id = ?",
            maintenanceId, "Maintenance record"));
    }

    public void requireDisposalAccess(Long disposalId) {
        CurrentUser u = current();
        if (u.admin()) return;
        requireOwnOffice(u, officeOf(
            "SELECT a.office_id FROM disposal_ledger d JOIN assets a ON a.asset_id = d.asset_id WHERE d.disposal_id = ?",
            disposalId, "Disposal record"));
    }

    // Can the given user see something in this office? Used to filter live updates.
    public boolean canSeeOffice(String username, Long officeId) {
        List<Object[]> rows = jdbcTemplate.query(
            "SELECT `role`, office_id FROM users WHERE LOWER(username) = LOWER(?)",
            (rs, rn) -> new Object[]{ rs.getString("role"), rs.getObject("office_id", Long.class) }, username);
        if (rows.isEmpty()) return false;
        if ("ADMIN".equalsIgnoreCase((String) rows.get(0)[0])) return true;
        Long own = (Long) rows.get(0)[1];
        return own != null && own.equals(officeId);
    }

    private Long officeOf(String sql, Long id, String what) {
        List<Long> rows = jdbcTemplate.query(sql, (rs, rn) -> rs.getObject(1, Long.class), id);
        if (rows.isEmpty()) throw new ResourceNotFoundException(what + " not found: " + id);
        return rows.get(0);
    }

    private void requireOwnOffice(CurrentUser u, Long officeId) {
        if (u.officeId() == null) {
            throw new ForbiddenException("Your account has no office assigned yet — ask an administrator to assign one.");
        }
        if (!u.officeId().equals(officeId)) {
            throw new ForbiddenException("This belongs to another office.");
        }
    }
}
