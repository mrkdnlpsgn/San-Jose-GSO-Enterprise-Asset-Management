package com.sanjose.inventory.service;

import com.sanjose.inventory.exception.ForbiddenException;
import com.sanjose.inventory.exception.ResourceNotFoundException;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Service;

import java.util.HashSet;
import java.util.List;
import java.util.Set;

// Role-based access: ADMIN sees and manages everything. STAFF only see, edit and update an
// asset (and its maintenance / disposal records, history and photos) when BOTH hold:
//   - the asset is in the office an admin assigned the account on the Personnel page, and
//   - the asset's accountable person is the account itself: the personnel record linked to the
//     account, or one with exactly the account's full name.
// A staff account without an office sees nothing. Adding assets, deleting records and
// approving staff requests are admin-only (see also SecurityConfig).
@Service
@RequiredArgsConstructor
public class AccessService {

    // matches no office, so a staff account without one gets empty lists
    private static final long NO_OFFICE = -1L;

    private final JdbcTemplate jdbcTemplate;

    public record CurrentUser(Long id, String username, boolean admin, Long officeId) {}

    // What one staff account may see, as a condition on an `assets` alias (see the class comment).
    public record StaffScope(long officeId, long userId) {
        public String sql(String assetAlias) {
            return assetAlias + ".office_id = ? AND " + assetAlias + ".personnel_id IN ("
                + "SELECT p.personnel_id FROM personnel p JOIN users u ON u.user_id = ? "
                + "WHERE p.user_id = u.user_id OR LOWER(p.full_name) = LOWER(u.full_name))";
        }

        public Object[] args() {
            return new Object[]{ officeId, userId };
        }
    }

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

    // Office filter for list queries: null = every office (admin). For staff this only narrows the
    // query; what they may actually see is staffScope() / visibleAssetIds().
    public Long scopeOfficeId() {
        CurrentUser u = current();
        if (u.admin()) return null;
        return u.officeId() != null ? u.officeId() : NO_OFFICE;
    }

    // null = admin (sees everything).
    public StaffScope staffScope() {
        CurrentUser u = current();
        if (u.admin()) return null;
        return new StaffScope(u.officeId() != null ? u.officeId() : NO_OFFICE, u.id());
    }

    // The assets the current staff account may see; null = admin (everything).
    public Set<Long> visibleAssetIds() {
        StaffScope scope = staffScope();
        if (scope == null) return null;
        return new HashSet<>(jdbcTemplate.queryForList(
            "SELECT a.asset_id FROM assets a WHERE " + scope.sql("a"), Long.class, scope.args()));
    }

    public void requireAdmin(String action) {
        if (!isAdmin()) throw new ForbiddenException("Only an administrator can " + action + ".");
    }

    public void requireAssetAccess(Long assetId) {
        CurrentUser u = current();
        if (u.admin()) return;
        requireOwnAsset(u, idOf("SELECT asset_id FROM assets WHERE asset_id = ?", assetId, "Asset"));
    }

    public void requireMaintenanceAccess(Long maintenanceId) {
        CurrentUser u = current();
        if (u.admin()) return;
        requireOwnAsset(u, idOf("SELECT asset_id FROM maintenance_ledger WHERE maintenance_id = ?",
            maintenanceId, "Maintenance record"));
    }

    public void requireDisposalAccess(Long disposalId) {
        CurrentUser u = current();
        if (u.admin()) return;
        requireOwnAsset(u, idOf("SELECT asset_id FROM disposal_ledger WHERE disposal_id = ?",
            disposalId, "Disposal record"));
    }

    // Can the given user see this asset? Used to filter live updates. null asset = admins only.
    public boolean canSeeAsset(String username, Long assetId) {
        List<Object[]> rows = jdbcTemplate.query(
            "SELECT user_id, `role`, office_id FROM users WHERE LOWER(username) = LOWER(?)",
            (rs, rn) -> new Object[]{ rs.getLong("user_id"), rs.getString("role"), rs.getObject("office_id", Long.class) },
            username);
        if (rows.isEmpty()) return false;
        if ("ADMIN".equalsIgnoreCase((String) rows.get(0)[1])) return true;
        Long officeId = (Long) rows.get(0)[2];
        if (assetId == null || officeId == null) return false;
        return isVisible(new StaffScope(officeId, (Long) rows.get(0)[0]), assetId);
    }

    private Long idOf(String sql, Long id, String what) {
        List<Long> rows = jdbcTemplate.query(sql, (rs, rn) -> rs.getObject(1, Long.class), id);
        if (rows.isEmpty()) throw new ResourceNotFoundException(what + " not found: " + id);
        return rows.get(0);
    }

    private boolean isVisible(StaffScope scope, Long assetId) {
        Object[] args = { assetId, scope.args()[0], scope.args()[1] };
        Integer n = jdbcTemplate.queryForObject(
            "SELECT COUNT(*) FROM assets a WHERE a.asset_id = ? AND " + scope.sql("a"), Integer.class, args);
        return n != null && n > 0;
    }

    private void requireOwnAsset(CurrentUser u, Long assetId) {
        if (u.officeId() == null) {
            throw new ForbiddenException("Your account has no office assigned yet — ask an administrator to assign one.");
        }
        if (!isVisible(new StaffScope(u.officeId(), u.id()), assetId)) {
            throw new ForbiddenException("This asset isn't assigned to you.");
        }
    }
}
