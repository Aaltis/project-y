package fi.breakwaterworks.crm.projects.model;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.math.BigDecimal;
import java.util.UUID;

@Entity
@Table(name = "project_charter")
@Getter @Setter @NoArgsConstructor
public class ProjectCharter {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @Column(name = "project_id", nullable = false)
    private UUID projectId;

    @Column(columnDefinition = "TEXT")
    private String objectives;

    @Column(name = "high_level_scope", columnDefinition = "TEXT")
    private String highLevelScope;

    @Column(name = "success_criteria", columnDefinition = "TEXT")
    private String successCriteria;

    @Column(name = "summary_budget", precision = 19, scale = 2)
    private BigDecimal summaryBudget;

    @Column(name = "key_risks", columnDefinition = "TEXT")
    private String keyRisks;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private CharterStatus status = CharterStatus.DRAFT;
}
