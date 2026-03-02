package fi.breakwaterworks.crm.projects.model;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.math.BigDecimal;
import java.util.UUID;

@Entity
@Table(name = "closure_report")
@Getter @Setter @NoArgsConstructor
public class ClosureReport {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @Column(name = "project_id", nullable = false)
    private UUID projectId;

    @Column(name = "outcomes_summary", columnDefinition = "TEXT")
    private String outcomesSummary;

    @Column(name = "budget_actual")
    private BigDecimal budgetActual;

    @Column(name = "schedule_actual")
    private String scheduleActual;

    @Column(name = "acceptance_summary", columnDefinition = "TEXT")
    private String acceptanceSummary;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private ClosureReportStatus status = ClosureReportStatus.DRAFT;
}
