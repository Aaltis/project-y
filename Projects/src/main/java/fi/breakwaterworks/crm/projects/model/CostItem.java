package fi.breakwaterworks.crm.projects.model;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.math.BigDecimal;
import java.util.UUID;

@Entity
@Table(name = "cost_item")
@Getter @Setter @NoArgsConstructor
public class CostItem {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @Column(name = "project_id", nullable = false)
    private UUID projectId;

    @Column(name = "wbs_item_id")
    private UUID wbsItemId;

    private String category;

    @Column(name = "planned_cost", precision = 19, scale = 2)
    private BigDecimal plannedCost;

    @Column(name = "actual_cost", precision = 19, scale = 2)
    private BigDecimal actualCost;
}
