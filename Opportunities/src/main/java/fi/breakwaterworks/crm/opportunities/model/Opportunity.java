package fi.breakwaterworks.crm.opportunities.model;

import jakarta.persistence.*;
import jakarta.validation.constraints.NotBlank;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import org.hibernate.annotations.UpdateTimestamp;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.UUID;

@Entity
@Table(name = "opportunity")
@Getter @Setter @NoArgsConstructor
public class Opportunity {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @Column(name = "account_id", nullable = false)
    private UUID accountId;

    @NotBlank
    @Column(nullable = false)
    private String name;

    private BigDecimal amount;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private OpportunityStage stage = OpportunityStage.PROSPECT;

    @Column(name = "close_date")
    private LocalDate closeDate;

    @Column(name = "owner_id", nullable = false)
    private String ownerId;

    @UpdateTimestamp
    @Column(name = "updated_at")
    private LocalDateTime updatedAt;
}
