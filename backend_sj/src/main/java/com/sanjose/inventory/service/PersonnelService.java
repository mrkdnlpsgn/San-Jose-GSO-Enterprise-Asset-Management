package com.sanjose.inventory.service;

import com.sanjose.inventory.dto.PersonnelRequest;
import com.sanjose.inventory.dto.UserResponse;
import com.sanjose.inventory.entity.Office;
import com.sanjose.inventory.entity.Personnel;
import com.sanjose.inventory.exception.ResourceNotFoundException;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.util.HtmlUtils;

import java.sql.Timestamp;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
@Transactional
public class PersonnelService {

    private final JdbcTemplate jdbcTemplate;
    private final AuditLogService auditLogService;
    private final UserService userService;
    private final EmailService emailService;
    private final OfficeAssignmentService officeAssignments;

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
        List<Personnel> list = search != null && !search.isBlank()
            ? jdbcTemplate.query("CALL sp_personnel_search(?)", PERSONNEL_MAPPER, search.trim())
            : jdbcTemplate.query("CALL sp_personnel_get_all()", PERSONNEL_MAPPER);
        Map<Long, List<OfficeAssignmentService.OfficeRef>> offices = officeAssignments.byPersonnel();
        list.forEach(p -> setOffices(p, offices.get(p.getId())));
        return list;
    }

    public Personnel findById(Long id) {
        List<Personnel> list = jdbcTemplate.query("CALL sp_personnel_get_by_id(?)", PERSONNEL_MAPPER, id);
        if (list.isEmpty()) throw new ResourceNotFoundException("Personnel not found: " + id);
        Personnel p = list.get(0);
        setOffices(p, officeAssignments.ofPersonnel(id));
        return p;
    }

    private static void setOffices(Personnel p, List<OfficeAssignmentService.OfficeRef> refs) {
        List<Office> offices = new ArrayList<>();
        if (refs != null) refs.forEach(r -> {
            Office o = new Office();
            o.setId(r.id());
            o.setOfficeName(r.officeName());
            offices.add(o);
        });
        p.setOffices(offices);
    }

    private static List<Long> officeIds(Personnel p) {
        return p.getOffices().stream().map(Office::getId).toList();
    }

    // Personnel records are the accounts (created/removed on the Accounts page). An admin
    // assigns each one's office here — it's the only place an account's office is set,
    // and sp_personnel_update copies it onto the account. The name always follows the account.
    public Personnel update(Long id, PersonnelRequest req) {
        Personnel existing = findById(id);
        if (existing.getUserId() == null) {
            throw new IllegalArgumentException("Only personnel linked to an account can be edited.");
        }
        // Several offices may be assigned; the primary one (officeId, else the first) is what
        // sp_personnel_update stores on the person and copies onto the account.
        Set<Long> chosen = new LinkedHashSet<>();
        if (req.getOfficeId() != null && req.getOfficeId() != 0) chosen.add(req.getOfficeId());
        if (req.getOfficeIds() != null) req.getOfficeIds().stream().filter(o -> o != null && o != 0).forEach(chosen::add);
        if (chosen.isEmpty()) {
            throw new IllegalArgumentException("Office is required.");
        }
        for (Long officeId : chosen) {
            Integer n = jdbcTemplate.queryForObject("SELECT COUNT(*) FROM offices WHERE office_id = ?", Integer.class, officeId);
            if (n == null || n == 0) throw new IllegalArgumentException("Office not found: " + officeId);
        }
        Long primary = chosen.iterator().next();
        jdbcTemplate.update("CALL sp_personnel_update(?, ?, ?, ?, ?)",
            id, existing.getFullName(), req.getPosition(),
            primary.intValue(),
            req.getContactInfo());
        officeAssignments.replace(id, new ArrayList<>(chosen));
        Personnel saved = findById(id);
        String names = saved.getOffices().stream().map(Office::getOfficeName).collect(Collectors.joining(", "));
        auditLogService.log("PERSONNEL_UPDATED", "Personnel", id, "personnel",
            "Updated: " + saved.getFullName() + " — office" + (saved.getOffices().size() > 1 ? "s " : " ") + (names.isEmpty() ? "none" : names));
        if (!saved.getOffices().isEmpty() && !new HashSet<>(officeIds(existing)).equals(new HashSet<>(officeIds(saved)))) {
            notifyOfficeAssigned(saved, existing.getOffices());
        }
        return saved;
    }

    // Only on an actual office change — re-saving the same offices or editing contact info sends nothing.
    private void notifyOfficeAssigned(Personnel saved, List<Office> previous) {
        UserResponse user = userService.findById(saved.getUserId());
        if (!Boolean.TRUE.equals(user.getIsActive()) || user.getEmail() == null || user.getEmail().isBlank()) return;
        String offices = saved.getOffices().stream().map(o -> HtmlUtils.htmlEscape(o.getOfficeName())).collect(Collectors.joining(", "));
        String before = previous.stream().map(o -> HtmlUtils.htmlEscape(o.getOfficeName())).collect(Collectors.joining(", "));
        boolean many = saved.getOffices().size() > 1;
        String html = "<p>Hello " + HtmlUtils.htmlEscape(saved.getFullName()) + ",</p>"
            + (previous.isEmpty()
                ? "<p>You have been assigned to " + (many ? "offices" : "an office") + " in the San Jose GSO Inventory Management System.</p>"
                : "<p>Your office assignment in the San Jose GSO Inventory Management System has been changed from <b>"
                    + before + "</b>.</p>")
            + "<p><b>Assigned office" + (many ? "s" : "") + ":</b> " + offices + "</p>"
            + "<p>When you sign in, you will see and manage the assets of " + (many ? "these offices" : "this office") + ".</p>"
            + "<p>If you think this is a mistake, please contact the GSO system administrator.</p>";
        String subject = many
            ? "You have been assigned to " + saved.getOffices().size() + " offices"
            : "You have been assigned to " + saved.getOffices().get(0).getOfficeName();
        emailService.send(user.getEmail(), subject, html);
    }
}
