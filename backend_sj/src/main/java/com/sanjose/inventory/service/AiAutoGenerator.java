package com.sanjose.inventory.service;

import com.sanjose.inventory.config.GeminiConfig;
import com.sanjose.inventory.dto.RecordChangedEvent;
import jakarta.annotation.PreDestroy;
import lombok.extern.slf4j.Slf4j;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.event.TransactionalEventListener;

import java.util.List;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.function.BooleanSupplier;
import java.util.function.Supplier;

// Writes the AI summary of a maintenance record / justification of a disposal record in the
// background when the record is created, edited or approved, so nobody has to press Generate.
// Everything else (asset recommendations, the dashboard period summary, the audit digest, and
// summaries for records saved before this existed) is only made when someone presses Generate:
// the Gemini free plan allows about 20 requests a day, and generating on every view or asset
// change used that up by midday.
//
// Jobs run one at a time on a single worker, spaced MIN_INTERVAL_MS apart to stay under
// Gemini's per-minute limit; a job already waiting isn't queued twice. When one finishes, an
// "ai" SSE event tells open screens to reload it (FAILED with a message if it couldn't).
@Slf4j
@Service
public class AiAutoGenerator {

    private static final long MIN_INTERVAL_MS = 6_000;
    private static final int MAX_QUEUED = 200;
    private static final Set<String> LEDGER_ACTIONS = Set.of("CREATED", "UPDATED", "APPROVED");

    private final GeminiConfig geminiConfig;
    private final JdbcTemplate jdbcTemplate;
    private final MaintenanceSummaryService maintenanceSummaryService;
    private final DisposalJustificationService disposalJustificationService;
    private final SseEmitterService sseEmitterService;

    private final ExecutorService worker = Executors.newSingleThreadExecutor(r -> {
        Thread t = new Thread(r, "ai-auto");
        t.setDaemon(true);
        return t;
    });
    private final Set<String> queued = ConcurrentHashMap.newKeySet();
    private long lastCallAt; // worker thread only

    public AiAutoGenerator(GeminiConfig geminiConfig, JdbcTemplate jdbcTemplate,
                           MaintenanceSummaryService maintenanceSummaryService,
                           DisposalJustificationService disposalJustificationService,
                           SseEmitterService sseEmitterService) {
        this.geminiConfig = geminiConfig;
        this.jdbcTemplate = jdbcTemplate;
        this.maintenanceSummaryService = maintenanceSummaryService;
        this.disposalJustificationService = disposalJustificationService;
        this.sseEmitterService = sseEmitterService;
    }

    @PreDestroy
    void shutdown() {
        worker.shutdownNow();
    }

    // Runs after the change commits (or right away outside a transaction), so the worker
    // reads the saved data.
    @TransactionalEventListener(fallbackExecution = true)
    public void onRecordChanged(RecordChangedEvent e) {
        if (!geminiConfig.isAvailable() || e.id() == null) return;
        if (!LEDGER_ACTIONS.contains(e.action())) return;
        if ("maintenance".equals(e.channel())) requestMaintenanceSummary(e.id());
        else if ("disposal".equals(e.channel())) requestDisposalJustification(e.id());
    }

    // The 404 body when nothing exists yet, plus — if AI is paused (quota used up) — the message
    // to show next to the Generate button.
    public java.util.Map<String, Object> notReady(String message) {
        java.util.Map<String, Object> body = new java.util.LinkedHashMap<>();
        body.put("message", message);
        body.put("generating", false);
        String unavailable = geminiConfig.unavailableMessage();
        if (unavailable != null) body.put("unavailable", unavailable);
        return body;
    }

    // Each returns false when AI is off or paused (or the queue is full), i.e. nothing is coming.

    public boolean requestMaintenanceSummary(Long maintenanceId) {
        return submit("maint:" + maintenanceId, "summary", maintenanceId,
            () -> firstLong("SELECT a.office_id FROM maintenance_ledger m JOIN assets a ON a.asset_id = m.asset_id WHERE m.maintenance_id = ?",
                maintenanceId),
            () -> { pace(); maintenanceSummaryService.generate(maintenanceId); return true; });
    }

    public boolean requestDisposalJustification(Long disposalId) {
        return submit("disp:" + disposalId, "justification", disposalId,
            () -> firstLong("SELECT a.office_id FROM disposal_ledger d JOIN assets a ON a.asset_id = d.asset_id WHERE d.disposal_id = ?",
                disposalId),
            () -> { pace(); disposalJustificationService.generate(disposalId); return true; });
    }

    // job returns true when it produced something new (false = nothing needed doing). Either way
    // the screens waiting on it hear back: READY, or FAILED with a message to show instead.
    private boolean submit(String key, String kind, Long id, Supplier<Long> officeOf, BooleanSupplier job) {
        if (!geminiConfig.isAvailable()) return false;
        if (queued.contains(key)) return true;
        if (queued.size() >= MAX_QUEUED) {
            log.warn("AI background queue is full ({}); skipping {}", MAX_QUEUED, key);
            return false;
        }
        if (!queued.add(key)) return true;
        worker.execute(() -> {
            queued.remove(key);   // a change arriving while this runs queues a fresh job
            try {
                if (job.getAsBoolean()) sseEmitterService.emitAiReady(kind, id, officeOf.get());
            } catch (Exception ex) {
                log.warn("Background AI job {} failed: {}", key, ex.getMessage());
                String reason = geminiConfig.unavailableMessage();
                try {
                    sseEmitterService.emitAiFailed(kind, id, officeOf.get(),
                        reason != null ? reason : "The AI couldn't prepare this right now. You can try Generate again.");
                } catch (Exception ignored) { /* nobody left to tell */ }
            }
        });
        return true;
    }

    private void pace() {
        long wait = lastCallAt + MIN_INTERVAL_MS - System.currentTimeMillis();
        if (wait > 0) {
            try {
                Thread.sleep(wait);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                throw new IllegalStateException("AI worker interrupted");
            }
        }
        lastCallAt = System.currentTimeMillis();
    }

    private Long firstLong(String sql, Long id) {
        List<Long> rows = jdbcTemplate.query(sql, (rs, rn) -> rs.getObject(1, Long.class), id);
        return rows.isEmpty() ? null : rows.get(0);
    }
}
