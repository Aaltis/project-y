package fi.breakwaterworks.logconsumer.listener;

import fi.breakwaterworks.logconsumer.model.RequestLog;
import fi.breakwaterworks.logconsumer.repository.RequestLogRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;

import java.time.Instant;
import java.util.Map;

@Slf4j
@Component
@RequiredArgsConstructor
public class RequestLogListener {

    private final RequestLogRepository requestLogRepository;

    @RabbitListener(queues = "request-logs")
    public void handleRequestLog(Map<String, Object> payload) {
        try {
            RequestLog entry = RequestLog.builder()
                .method((String) payload.get("method"))
                .path((String) payload.get("path"))
                .status(payload.get("status") instanceof Number n ? n.intValue() : null)
                .durationMs(payload.get("durationMs") instanceof Number n ? n.longValue() : null)
                .username((String) payload.get("username"))
                .timestamp(payload.get("timestamp") != null
                    ? Instant.parse(payload.get("timestamp").toString())
                    : Instant.now())
                .build();

            requestLogRepository.save(entry);
            log.info("Logged: {} {} -> {} ({}ms) user={}",
                entry.getMethod(), entry.getPath(), entry.getStatus(),
                entry.getDurationMs(), entry.getUsername());

        } catch (Exception e) {
            // Log but do not rethrow — prevents infinite re-queue loop for malformed messages
            log.error("Failed to process request log message: {}", payload, e);
        }
    }
}
