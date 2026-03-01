package fi.breakwaterworks.crm.projects.model;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import org.hibernate.annotations.CreationTimestamp;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.UUID;

@Entity
@Table(name = "status_report")
@Getter @Setter @NoArgsConstructor
public class StatusReport {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @Column(name = "project_id", nullable = false)
    private UUID projectId;

    @Column(name = "period_start", nullable = false)
    private LocalDate periodStart;

    @Column(name = "period_end", nullable = false)
    private LocalDate periodEnd;

    @Column(columnDefinition = "TEXT")
    private String summary;

    @Enumerated(EnumType.STRING)
    @Column(name = "rag_scope", nullable = false)
    private RagStatus ragScope = RagStatus.GREEN;

    @Enumerated(EnumType.STRING)
    @Column(name = "rag_schedule", nullable = false)
    private RagStatus ragSchedule = RagStatus.GREEN;

    @Enumerated(EnumType.STRING)
    @Column(name = "rag_cost", nullable = false)
    private RagStatus ragCost = RagStatus.GREEN;

    @Column(name = "key_risks", columnDefinition = "TEXT")
    private String keyRisks;

    @Column(name = "key_issues", columnDefinition = "TEXT")
    private String keyIssues;

    @Column(name = "created_by", nullable = false)
    private String createdBy;

    @CreationTimestamp
    @Column(name = "created_at", updatable = false)
    private LocalDateTime createdAt;
}
