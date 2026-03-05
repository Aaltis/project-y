package fi.breakwaterworks.gateway.ratelimit;

import io.github.bucket4j.Bandwidth;
import io.github.bucket4j.Bucket;
import org.springframework.stereotype.Component;

import java.time.Duration;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;

@Component
public class RateLimiterRegistry {

    // One bucket per username, lazily created on first request
    private final ConcurrentMap<String, Bucket> buckets = new ConcurrentHashMap<>();

    public Bucket getBucket(String username) {
        return buckets.computeIfAbsent(username, this::newBucket);
    }

    private Bucket newBucket(String username) {
        Bandwidth limit = Bandwidth.builder()
            .capacity(20)
            .refillGreedy(20, Duration.ofSeconds(1))
            .build();
        return Bucket.builder()
            .addLimit(limit)
            .build();
    }
}
