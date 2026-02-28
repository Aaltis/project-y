package fi.breakwaterworks.gateway.model;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.Instant;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class RequestLogMessage {
    private String method;
    private String path;
    private Integer status;
    private Long durationMs;
    private String username;
    private Instant timestamp;
}
