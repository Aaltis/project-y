package fi.breakwaterworks.crm.projects.model;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import org.hibernate.annotations.CreationTimestamp;

import java.time.LocalDateTime;
import java.util.UUID;

@Entity
@Table(name = "baseline_set")
@Getter @Setter @NoArgsConstructor
public class BaselineSet {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @Column(name = "project_id", nullable = false)
    private UUID projectId;

    @Column(nullable = false)
    private int version;

    @Column(name = "scope_snapshot", columnDefinition = "TEXT")
    private String scopeSnapshot;

    @Column(name = "schedule_snapshot", columnDefinition = "TEXT")
    private String scheduleSnapshot;

    @Column(name = "cost_snapshot", columnDefinition = "TEXT")
    private String costSnapshot;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private BaselineStatus status = BaselineStatus.DRAFT;

    @Column(name = "created_by", nullable = false)
    private String createdBy;

    @CreationTimestamp
    @Column(name = "created_at", updatable = false)
    private LocalDateTime createdAt;

    /** Set when this baseline was created as a result of an approved change request. */
    @Column(name = "change_request_id")
    private UUID changeRequestId;
}
