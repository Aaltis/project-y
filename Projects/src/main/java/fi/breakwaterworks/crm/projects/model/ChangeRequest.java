package fi.breakwaterworks.crm.projects.model;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import org.hibernate.annotations.CreationTimestamp;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.UUID;

@Entity
@Table(name = "change_request")
@Getter @Setter @NoArgsConstructor
public class ChangeRequest {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @Column(name = "project_id", nullable = false)
    private UUID projectId;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private ChangeRequestType type;

    @Column(nullable = false, columnDefinition = "TEXT")
    private String description;

    @Column(name = "impact_scope", columnDefinition = "TEXT")
    private String impactScope;

    @Column(name = "impact_schedule_days")
    private Integer impactScheduleDays;

    @Column(name = "impact_cost")
    private BigDecimal impactCost;

    @Column(name = "submitted_by", nullable = false)
    private String submittedBy;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private ChangeRequestStatus status = ChangeRequestStatus.DRAFT;

    @CreationTimestamp
    @Column(name = "created_at", updatable = false)
    private LocalDateTime createdAt;
}
