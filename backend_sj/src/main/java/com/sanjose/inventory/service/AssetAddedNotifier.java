package com.sanjose.inventory.service;

import com.sanjose.inventory.config.AppTime;
import com.sanjose.inventory.entity.Asset;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.web.util.HtmlUtils;

import java.time.format.DateTimeFormatter;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;

// Emails an office when assets are added to it: one message per office per save (an import of many
// assets is one email listing them), to the office's active accounts with an email address - the
// people assigned to it and its head - except the person who added them. Sent only once the save
// has gone through, so a failed save tells no one.
@Slf4j
@Service
@RequiredArgsConstructor
public class AssetAddedNotifier {

    private static final int MAX_LISTED = 50;
    private static final DateTimeFormatter DATE = DateTimeFormatter.ofPattern("MMMM d, yyyy");

    private final JdbcTemplate jdbcTemplate;
    private final EmailService emailService;

    private record Recipient(String email, String name) {}

    public void notifyAdded(List<Asset> assets) {
        if (assets == null || assets.isEmpty() || !emailService.isEnabled()) return;
        String actor = SecurityContextHolder.getContext().getAuthentication() != null
            ? SecurityContextHolder.getContext().getAuthentication().getName() : null;
        Map<Long, List<Asset>> byOffice = new LinkedHashMap<>();
        for (Asset a : assets) {
            if (a != null && a.getOffice() != null && a.getOffice().getId() != null) {
                byOffice.computeIfAbsent(a.getOffice().getId(), k -> new java.util.ArrayList<>()).add(a);
            }
        }
        if (byOffice.isEmpty()) return;
        Runnable send = () -> byOffice.forEach((officeId, list) -> sendToOffice(officeId, list, actor));
        if (TransactionSynchronizationManager.isSynchronizationActive()) {
            TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
                @Override
                public void afterCommit() { send.run(); }
            });
        } else {
            send.run();
        }
    }

    private void sendToOffice(Long officeId, List<Asset> assets, String actor) {
        try {
            List<Recipient> recipients = recipients(officeId, actor);
            if (recipients.isEmpty()) return;
            String office = assets.get(0).getOffice().getOfficeName();
            String addedBy = actor == null ? "the GSO" : jdbcTemplate.query(
                "SELECT COALESCE(NULLIF(full_name, ''), username) FROM users WHERE LOWER(username) = LOWER(?)",
                (rs, n) -> rs.getString(1), actor).stream().findFirst().orElse(actor);
            String subject = assets.size() == 1
                ? "New asset added to " + office + ": " + assets.get(0).getPropertyNumber()
                : assets.size() + " new assets added to " + office;
            for (Recipient r : recipients) {
                emailService.send(r.email(), subject, html(r.name(), office, assets, addedBy));
            }
            log.info("Asset added notice for {} sent to {} recipient(s)", office, recipients.size());
        } catch (RuntimeException e) {
            log.warn("Could not send the asset added notice for office {}", officeId, e);
        }
    }

    private List<Recipient> recipients(Long officeId, String actor) {
        return jdbcTemplate.query("""
            SELECT DISTINCT u.email, COALESCE(NULLIF(u.full_name, ''), u.username) AS name
            FROM users u
            WHERE u.is_active = 1 AND u.email IS NOT NULL AND u.email <> ''
              AND (? IS NULL OR LOWER(u.username) <> LOWER(?))
              AND (u.office_id = ?
                   OR u.user_id = (SELECT head_user_id FROM offices WHERE office_id = ?)
                   OR u.user_id IN (SELECT p.user_id FROM personnel p
                                    JOIN personnel_offices po ON po.personnel_id = p.personnel_id
                                    WHERE po.office_id = ?))
            """, (rs, n) -> new Recipient(rs.getString("email"), rs.getString("name")),
            actor, actor, officeId, officeId, officeId);
    }

    private static String html(String name, String office, List<Asset> assets, String addedBy) {
        StringBuilder rows = new StringBuilder();
        for (Asset a : assets.subList(0, Math.min(assets.size(), MAX_LISTED))) {
            rows.append("<tr>")
                .append(cell(a.getPropertyNumber()))
                .append(cell(a.getDescription()))
                .append(cell(a.getCategory() != null ? a.getCategory().getCategoryName() : null))
                .append(cell(a.getAccountablePerson() != null ? a.getAccountablePerson().getFullName() : null))
                .append("</tr>");
        }
        String th = "style=\"text-align:left;padding:6px 8px;border-bottom:1px solid #ccc;\"";
        boolean one = assets.size() == 1;
        return "<p>Hello " + esc(name) + ",</p>"
            + "<p>" + (one ? "A new asset has" : assets.size() + " new assets have") + " been added to <b>" + esc(office)
            + "</b> in the San Jose GSO Enterprise Asset Management System by " + esc(addedBy)
            + " on " + AppTime.today().format(DATE) + ".</p>"
            + "<table style=\"border-collapse:collapse;font-size:14px;\"><thead><tr>"
            + "<th " + th + ">Property No.</th><th " + th + ">Description</th><th " + th + ">Category</th><th " + th + ">Accountable</th>"
            + "</tr></thead><tbody>" + rows + "</tbody></table>"
            + (assets.size() > MAX_LISTED ? "<p>And " + (assets.size() - MAX_LISTED) + " more. Sign in to see them all.</p>" : "")
            + "<p>Sign in to the system to see " + (one ? "its" : "their") + " details. If something here is not right, "
            + "please contact the General Services Office.</p>";
    }

    private static String cell(String v) {
        return "<td style=\"padding:6px 8px;border-bottom:1px solid #eee;\">" + esc(v == null || v.isBlank() ? "N/A" : v) + "</td>";
    }

    private static String esc(String v) {
        return HtmlUtils.htmlEscape(Objects.toString(v, ""));
    }
}
