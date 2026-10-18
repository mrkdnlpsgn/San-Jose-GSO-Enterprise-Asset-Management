package com.sanjose.inventory.service;

import com.sanjose.inventory.exception.ForbiddenException;
import com.sanjose.inventory.exception.ResourceNotFoundException;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Service;

import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

// Role-based access: ADMIN sees and manages everything. STAFF only see, edit and update an
// asset (and its maintenance / disposal records, history and photos) when BOTH hold:
//   - the asset is in one of the offices an admin assigned the account on the Personnel page, and
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
    private final OfficeAssignmentService officeAssignments;

    // officeId = primary office; officeIds = every office assigned (primary first, may be empty)
    public record CurrentUser(Long id, String username, boolean admin, Long officeId, List<Long> officeIds) {
        public boolean inOffice(Long officeId) {
            return officeId != null && officeIds.contains(officeId);
        }
    }

    // What one staff account may see, as a condition on an `assets` alias (see the class comment).
    public record StaffScope(List<Long> officeIds, long userId) {
        public StaffScope {
            officeIds = officeIds == null || officeIds.isEmpty() ? List.of(NO_OFFICE) : List.copyOf(officeIds);
        }

        public String sql(String assetAlias) {
            String marks = String.join(", ", Collections.nCopies(officeIds.size(), "?"));
            return assetAlias + ".office_id IN (" + marks + ") AND " + assetAlias + ".personnel_id IN ("
                + "SELECT p.personnel_id FROM personnel p JOIN users u ON u.user_id = ? "
                + "WHERE p.user_id = u.user_id OR LOWER(p.full_name) = LOWER(u.full_name))";
        }

        public Object[] args() {
            Object[] out = new Object[officeIds.size() + 1];
            for (int i = 0; i < officeIds.size(); i++) out[i] = officeIds.get(i);
            out[officeIds.size()] = userId;
            return out;
        }
    }

    public CurrentUser current() {
        var auth = SecurityContextHolder.getContext().getAuthentication();
        if (auth == null) throw new ForbiddenException("Not signed in.");
        List<Object[]> rows = jdbcTemplate.query(
            "SELECT user_id, username, `role`, office_id FROM users WHERE LOWER(username) = LOWER(?)",
            (rs, rn) -> new Object[]{ rs.getLong("user_id"), rs.getString("username"),
                "ADMIN".equalsIgnoreCase(rs.getString("role")), rs.getObject("office_id", Long.class) },
            auth.getName());
        if (rows.isEmpty()) throw new ForbiddenException("Account not found.");
        Object[] r = rows.get(0);
        Long id = (Long) r[0];
        return new CurrentUser(id, (String) r[1], (Boolean) r[2], (Long) r[3], officeAssignments.officeIdsOfUser(id));
    }

    public boolean isAdmin() {
        return current().admin();
    }

    // Office filter for list queries: null = every office (admin, or staff in several offices —
    // the queries take one office). For staff this only narrows the query; what they may actually
    // see is staffScope() / visibleAssetIds().
    public Long scopeOfficeId() {
        CurrentUser u = current();
        if (u.admin()) return null;
        if (u.officeIds().isEmpty()) return NO_OFFICE;
        return u.officeIds().size() == 1 ? u.officeIds().get(0) : null;
    }

    // null = admin (sees everything).
    public StaffScope staffScope() {
        CurrentUser u = current();
        if (u.admin()) return null;
        return new StaffScope(u.officeIds(), u.id());
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
            "SELECT user_id, `role` FROM users WHERE LOWER(username) = LOWER(?)",
            (rs, rn) -> new Object[]{ rs.getLong("user_id"), rs.getString("role") },
            username);
        if (rows.isEmpty()) return false;
        if ("ADMIN".equalsIgnoreCase((String) rows.get(0)[1])) return true;
        if (assetId == null) return false;
        Long userId = (Long) rows.get(0)[0];
        List<Long> officeIds = officeAssignments.officeIdsOfUser(userId);
        if (officeIds.isEmpty()) return false;
        return isVisible(new StaffScope(officeIds, userId), assetId);
    }

    private Long idOf(String sql, Long id, String what) {
        List<Long> rows = jdbcTemplate.query(sql, (rs, rn) -> rs.getObject(1, Long.class), id);
        if (rows.isEmpty()) throw new ResourceNotFoundException(what + " not found: " + id);
        return rows.get(0);
    }

    private boolean isVisible(StaffScope scope, Long assetId) {
        Object[] scoped = scope.args();
        Object[] args = new Object[scoped.length + 1];
        args[0] = assetId;
        System.arraycopy(scoped, 0, args, 1, scoped.length);
        Integer n = jdbcTemplate.queryForObject(
            "SELECT COUNT(*) FROM assets a WHERE a.asset_id = ? AND " + scope.sql("a"), Integer.class, args);
        return n != null && n > 0;
    }

    private void requireOwnAsset(CurrentUser u, Long assetId) {
        if (u.officeIds().isEmpty()) {
            throw new ForbiddenException("Your account has no office assigned yet — ask an administrator to assign one.");
        }
        if (!isVisible(new StaffScope(u.officeIds(), u.id()), assetId)) {
            throw new ForbiddenException("This asset isn't assigned to you.");
        }
    }
}
