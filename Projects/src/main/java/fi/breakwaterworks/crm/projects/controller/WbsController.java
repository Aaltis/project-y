package fi.breakwaterworks.crm.projects.controller;

import fi.breakwaterworks.crm.projects.model.WbsItem;
import fi.breakwaterworks.crm.projects.service.ProjectPlanningService;
import lombok.Data;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import java.util.List;
import java.util.UUID;

@RestController
@RequestMapping("/api/projects/{projectId}/wbs")
@RequiredArgsConstructor
public class WbsController {

    private final ProjectPlanningService planningService;

    @GetMapping
    @PreAuthorize("@projectPerm.isMember(#projectId, authentication)")
    public List<WbsItem> list(@PathVariable UUID projectId) {
        return planningService.listWbs(projectId);
    }

    @PostMapping
    @PreAuthorize("@projectPerm.hasRole(#projectId, 'PM', authentication)")
    public ResponseEntity<WbsItem> create(@PathVariable UUID projectId,
                                           @Valid @RequestBody WbsRequest body) {
        return ResponseEntity.ok(planningService.addWbsItem(
                projectId, body.getName(), body.getDescription(),
                body.getWbsCode(), body.getParentId()));
    }

    @Data
    static class WbsRequest {
        @NotBlank
        private String name;
        private String description;
        private String wbsCode;
        private UUID parentId;
    }
}
