package fi.breakwaterworks.crm.opportunities.model;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.Instant;
import java.util.UUID;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class StageChangedEvent {
    private UUID opportunityId;
    private String fromStage;
    private String toStage;
    private String changedBy;
    private Instant timestamp;
}
