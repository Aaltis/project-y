package fi.breakwaterworks.crm.projects.model;

import jakarta.persistence.*;
import jakarta.validation.constraints.NotBlank;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.util.UUID;

@Entity
@Table(name = "stakeholder_register")
@Getter @Setter @NoArgsConstructor
public class StakeholderRegister {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @Column(name = "project_id", nullable = false)
    private UUID projectId;

    @NotBlank
    @Column(nullable = false)
    private String name;

    @Column(name = "user_id")
    private String userId;

    private String influence;

    private String interest;

    @Column(name = "engagement_level")
    private String engagementLevel;
}
