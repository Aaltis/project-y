package fi.breakwaterworks.crm.projects.controller;

import fi.breakwaterworks.crm.projects.model.CostItem;
import fi.breakwaterworks.crm.projects.service.ProjectPlanningService;
import lombok.Data;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

import java.math.BigDecimal;
import java.util.List;
import java.util.UUID;

@RestController
@RequestMapping("/api/projects/{projectId}/cost-items")
@RequiredArgsConstructor
public class CostItemController {

    private final ProjectPlanningService planningService;

    @GetMapping
    @PreAuthorize("@projectPerm.isMember(#projectId, authentication)")
    public List<CostItem> list(@PathVariable UUID projectId) {
        return planningService.listCostItems(projectId);
    }

    @PostMapping
    @PreAuthorize("@projectPerm.hasRole(#projectId, 'PM', authentication)")
    public ResponseEntity<CostItem> create(@PathVariable UUID projectId,
                                            @RequestBody CostItemRequest body) {
        return ResponseEntity.ok(planningService.addCostItem(
                projectId, body.getWbsItemId(), body.getCategory(), body.getPlannedCost()));
    }

    @Data
    static class CostItemRequest {
        private UUID wbsItemId;
        private String category;
        private BigDecimal plannedCost;
    }
}
