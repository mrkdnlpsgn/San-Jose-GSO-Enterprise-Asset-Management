package com.sanjose.inventory.service;

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
@Slf4j
@Service
public class SseEmitterService {

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
        broadcast("asset", new SseEvent(action, id, data, currentUsername()));
    }

    public void emitMaintenance(String action, Long id, Object data) {
        broadcast("maintenance", new SseEvent(action, id, data, currentUsername()));
    }

    public void emitDisposal(String action, Long id, Object data) {
        broadcast("disposal", new SseEvent(action, id, data, currentUsername()));
    }

    private void broadcastPresence() {
        List<String> online = emitters.values().stream().distinct().sorted().toList();
        broadcast("presence", new SseEvent("SNAPSHOT", null, online, null));
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
