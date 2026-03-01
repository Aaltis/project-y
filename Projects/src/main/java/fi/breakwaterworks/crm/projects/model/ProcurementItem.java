package fi.breakwaterworks.crm.projects.model;

import jakarta.persistence.*;
import jakarta.validation.constraints.NotBlank;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.math.BigDecimal;
import java.util.UUID;

@Entity
@Table(name = "procurement_item")
@Getter @Setter @NoArgsConstructor
public class ProcurementItem {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @Column(name = "project_id", nullable = false)
    private UUID projectId;

    @NotBlank
    @Column(nullable = false)
    private String item;

    private String vendor;

    @Column(precision = 19, scale = 2)
    private BigDecimal estimate;

    private String status;
}
