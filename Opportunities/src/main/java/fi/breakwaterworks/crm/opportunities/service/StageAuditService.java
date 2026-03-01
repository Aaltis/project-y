package fi.breakwaterworks.crm.opportunities.service;

import fi.breakwaterworks.crm.opportunities.config.RabbitMQConfig;
import fi.breakwaterworks.crm.opportunities.model.OpportunityStage;
import fi.breakwaterworks.crm.opportunities.model.StageChangedEvent;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.security.core.Authentication;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;

import java.time.Instant;
import java.util.Map;
import java.util.UUID;

@Service
@Slf4j
@RequiredArgsConstructor
public class StageAuditService {

    @Value("${activities.uri}")
    private String activitiesUri;

    private final RabbitTemplate rabbitTemplate;

    /** Best-effort — never throws. Failures are logged and swallowed. */
    public void logStageChange(UUID opportunityId, OpportunityStage from, OpportunityStage to, Authentication auth) {
        Jwt jwt = (Jwt) auth.getPrincipal();
        String username = jwt.getClaimAsString("preferred_username");
        String token = jwt.getTokenValue();

        postAuditActivity(opportunityId, from, to, username, token);
        publishStageChangedEvent(opportunityId, from, to, username);
    }

    private void postAuditActivity(UUID opportunityId, OpportunityStage from, OpportunityStage to,
                                   String username, String token) {
        Map<String, Object> body = Map.of(
                "type", "NOTE",
                "text", "Stage changed " + from + " -> " + to + " by " + username
        );
        try {
            RestClient.create().post()
                    .uri(activitiesUri + "/api/opportunities/" + opportunityId + "/activities")
                    .header("Authorization", "Bearer " + token)
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(body)
                    .retrieve()
                    .toBodilessEntity();
        } catch (Exception e) {
            log.warn("Failed to create audit activity for opportunity {}: {}", opportunityId, e.getMessage());
        }
    }

    private void publishStageChangedEvent(UUID opportunityId, OpportunityStage from,
                                          OpportunityStage to, String username) {
        try {
            StageChangedEvent event = StageChangedEvent.builder()
                    .opportunityId(opportunityId)
                    .fromStage(from.name())
                    .toStage(to.name())
                    .changedBy(username)
                    .timestamp(Instant.now())
                    .build();
            rabbitTemplate.convertAndSend(RabbitMQConfig.QUEUE_NAME, event);
            log.debug("Published stage-changed event: {} {} -> {}", opportunityId, from, to);
        } catch (Exception e) {
            log.warn("Failed to publish stage-changed event for opportunity {}: {}", opportunityId, e.getMessage());
        }
    }
}
