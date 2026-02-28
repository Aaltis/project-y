package fi.breakwaterworks.gateway.filter;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import fi.breakwaterworks.gateway.model.RequestLogMessage;
import fi.breakwaterworks.gateway.ratelimit.RateLimiterRegistry;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.cloud.gateway.filter.GatewayFilterChain;
import org.springframework.cloud.gateway.filter.GlobalFilter;
import org.springframework.core.Ordered;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.web.server.ServerWebExchange;
import reactor.core.publisher.Mono;

import java.time.Instant;
import java.util.Base64;

@Slf4j
@Component
@RequiredArgsConstructor
public class RequestLoggingGlobalFilter implements GlobalFilter, Ordered {

    private static final String QUEUE = "request-logs";

    private final RateLimiterRegistry rateLimiterRegistry;
    private final RabbitTemplate rabbitTemplate;
    private final ObjectMapper objectMapper;

    // Run early so rate limiting happens before routing
    @Override
    public int getOrder() {
        return -1;
    }

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, GatewayFilterChain chain) {
        String path = exchange.getRequest().getURI().getPath();

        // Only intercept /api/** — Keycloak /auth/** passes through untouched
        if (!path.startsWith("/api/")) {
            return chain.filter(exchange);
        }

        String username = extractUsername(exchange);
        Instant start = Instant.now();

        // Bucket4j tryConsume is thread-safe and synchronous — wrap in Mono for reactive chain
        return Mono.fromCallable(() -> rateLimiterRegistry.getBucket(username).tryConsume(1))
            .flatMap(allowed -> {
                if (!allowed) {
                    log.warn("Rate limit exceeded for user '{}' on {} {}", username,
                        exchange.getRequest().getMethod(), path);
                    exchange.getResponse().setStatusCode(HttpStatus.TOO_MANY_REQUESTS);
                    return exchange.getResponse().setComplete();
                }

                return chain.filter(exchange)
                    .doFinally(signal -> publishLog(exchange, path, username, start));
            });
    }

    private void publishLog(ServerWebExchange exchange, String path, String username, Instant start) {
        try {
            int status = exchange.getResponse().getStatusCode() != null
                ? exchange.getResponse().getStatusCode().value()
                : 0;

            long durationMs = Instant.now().toEpochMilli() - start.toEpochMilli();

            RequestLogMessage msg = RequestLogMessage.builder()
                .method(exchange.getRequest().getMethod().name())
                .path(path)
                .status(status)
                .durationMs(durationMs)
                .username(username)
                .timestamp(start)
                .build();

            rabbitTemplate.convertAndSend(QUEUE, msg);
            log.debug("Published log: {} {} -> {} ({}ms) user={}", msg.getMethod(), path, status, durationMs, username);

        } catch (Exception e) {
            // Never let a logging failure affect the API response
            log.error("Failed to publish request log to RabbitMQ", e);
        }
    }

    private String extractUsername(ServerWebExchange exchange) {
        String authHeader = exchange.getRequest().getHeaders().getFirst(HttpHeaders.AUTHORIZATION);

        if (authHeader == null || !authHeader.startsWith("Bearer ")) {
            return "anonymous";
        }

        try {
            String token = authHeader.substring(7);
            String[] parts = token.split("\\.");
            if (parts.length < 2) return "anonymous";

            // Pad Base64 URL-encoded payload if needed
            String payload = parts[1];
            int padding = (4 - payload.length() % 4) % 4;
            payload = payload + "=".repeat(padding);

            String json = new String(Base64.getUrlDecoder().decode(payload));
            JsonNode node = objectMapper.readTree(json);

            // Keycloak sets preferred_username to the login name; sub is a UUID
            if (node.has("preferred_username")) {
                return node.get("preferred_username").asText("anonymous");
            }
            return node.has("sub") ? node.get("sub").asText("anonymous") : "anonymous";

        } catch (Exception e) {
            log.debug("Could not extract username from JWT", e);
            return "anonymous";
        }
    }
}
