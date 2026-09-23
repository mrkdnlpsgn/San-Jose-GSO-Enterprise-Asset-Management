package com.sanjose.inventory.service;

import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import com.sanjose.inventory.dto.SseEvent;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Service;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

import java.io.IOException;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

// Broadcasts asset/maintenance/disposal changes to every connected client so
// open tabs stay in sync without polling, plus a "presence" channel listing
// distinct online usernames. Payload contract per data channel: data present
// -> upsert by id; action "DELETED" -> remove by id (id always present, plus
// a minimal `data` for display purposes only); data absent otherwise ->
// caller should refetch (the asset condition-change cascade, which touches
// records this service can't cheaply re-fetch). Every event also carries the
// acting user's username so clients can skip toasting their own actions.
//
// Data events are only delivered to users allowed to see the office the record belongs
// to (admins: all; staff: their assigned office — see AccessService).
@Slf4j
@Service
@RequiredArgsConstructor
public class SseEmitterService {

    private final JdbcTemplate jdbcTemplate;
    private final AccessService accessService;

    // Keyed by emitter so multiple tabs/connections from the same user are
    // tracked individually, but presence collapses them back to distinct usernames.
    private final Map<SseEmitter, String> emitters = new ConcurrentHashMap<>();

    public SseEmitter subscribe(String username) {
        // No fixed timeout here (Long.MAX_VALUE would overflow the deadline math
        // Spring's async support does internally) — spring.mvc.async.request-timeout=-1
        // disables the timeout at the framework level instead.
        SseEmitter emitter = new SseEmitter();
        emitters.put(emitter, username);
        Runnable cleanup = () -> {
            emitters.remove(emitter);
            broadcastPresence();
        };
        emitter.onCompletion(cleanup);
        emitter.onTimeout(cleanup);
        emitter.onError(e -> cleanup.run());
        broadcastPresence();
        return emitter;
    }

    public void emitAsset(String action, Long id, Object data) {
        broadcastScoped("asset", new SseEvent(action, id, data, currentUsername()),
            officeOf("SELECT office_id FROM assets WHERE asset_id = ?", id));
    }

    public void emitMaintenance(String action, Long id, Object data) {
        // "CHANGED" (condition cascade) carries the asset id rather than a record id
        broadcastScoped("maintenance", new SseEvent(action, id, data, currentUsername()), "CHANGED".equals(action)
            ? officeOf("SELECT office_id FROM assets WHERE asset_id = ?", id)
            : officeOf("SELECT a.office_id FROM maintenance_ledger m JOIN assets a ON a.asset_id = m.asset_id WHERE m.maintenance_id = ?", id));
    }

    public void emitDisposal(String action, Long id, Object data) {
        broadcastScoped("disposal", new SseEvent(action, id, data, currentUsername()), "CHANGED".equals(action)
            ? officeOf("SELECT office_id FROM assets WHERE asset_id = ?", id)
            : officeOf("SELECT a.office_id FROM disposal_ledger d JOIN assets a ON a.asset_id = d.asset_id WHERE d.disposal_id = ?", id));
    }

    private void broadcastPresence() {
        List<String> online = emitters.values().stream().distinct().sorted().toList();
        broadcast("presence", new SseEvent("SNAPSHOT", null, online, null));
    }

    private Long officeOf(String sql, Long id) {
        if (id == null) return null;
        List<Long> rows = jdbcTemplate.query(sql, (rs, rn) -> rs.getObject(1, Long.class), id);
        return rows.isEmpty() ? null : rows.get(0);
    }

    private void broadcastScoped(String eventName, SseEvent event, Long officeId) {
        Map<String, Boolean> allowed = new java.util.HashMap<>();
        for (Map.Entry<SseEmitter, String> e : emitters.entrySet()) {
            boolean ok = allowed.computeIfAbsent(e.getValue(), u -> accessService.canSeeOffice(u, officeId));
            if (!ok) continue;
            try {
                e.getKey().send(SseEmitter.event().name(eventName).data(event));
            } catch (IOException | IllegalStateException ex) {
                emitters.remove(e.getKey());
            }
        }
    }

    private void broadcast(String eventName, SseEvent event) {
        for (SseEmitter emitter : emitters.keySet()) {
            try {
                emitter.send(SseEmitter.event().name(eventName).data(event));
            } catch (IOException | IllegalStateException e) {
                emitters.remove(emitter);
            }
        }
    }

    private String currentUsername() {
        var auth = SecurityContextHolder.getContext().getAuthentication();
        return auth != null ? auth.getName() : null;
    }

    // Keeps intermediary proxies/load balancers from idling out the connection.
    @Scheduled(fixedRate = 15_000)
    public void heartbeat() {
        for (SseEmitter emitter : emitters.keySet()) {
            try {
                emitter.send(SseEmitter.event().comment("keep-alive"));
            } catch (IOException | IllegalStateException e) {
                emitters.remove(emitter);
            }
        }
    }
}
