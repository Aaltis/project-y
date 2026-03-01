package fi.breakwaterworks.crm.projects.model;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.LocalDate;
import java.util.UUID;

@Entity
@Table(name = "decision_log")
@Getter @Setter @NoArgsConstructor
public class DecisionLog {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @Column(name = "project_id", nullable = false)
    private UUID projectId;

    @Column(nullable = false, columnDefinition = "TEXT")
    private String decision;

    @Column(name = "decision_date", nullable = false)
    private LocalDate decisionDate;

    @Column(name = "made_by", nullable = false)
    private String madeBy;
}
