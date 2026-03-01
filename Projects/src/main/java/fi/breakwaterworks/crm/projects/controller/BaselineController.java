package fi.breakwaterworks.crm.projects.controller;

import fi.breakwaterworks.crm.projects.model.BaselineSet;
import fi.breakwaterworks.crm.projects.service.ProjectPlanningService;
import lombok.Data;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.UUID;

@RestController
@RequestMapping("/api/projects/{projectId}/baselines")
@RequiredArgsConstructor
public class BaselineController {

    private final ProjectPlanningService planningService;

    @GetMapping
    @PreAuthorize("@projectPerm.isMember(#projectId, authentication)")
    public List<BaselineSet> list(@PathVariable UUID projectId) {
        return planningService.listBaselines(projectId);
    }

    /**
     * Create a new baseline (snapshot of current WBS, tasks, cost items).
     * Project must be ACTIVE. PM only. Version auto-increments per project.
     */
    @PostMapping
    @PreAuthorize("@projectPerm.hasRole(#projectId, 'PM', authentication)")
    public ResponseEntity<BaselineSet> create(@PathVariable UUID projectId, Authentication auth) {
        return ResponseEntity.ok(planningService.createBaseline(projectId, sub(auth)));
    }

    /**
     * Submit a baseline draft for sponsor approval. PM only.
     */
    @PostMapping("/{version}/submit")
    @PreAuthorize("@projectPerm.hasRole(#projectId, 'PM', authentication)")
    public ResponseEntity<BaselineSet> submit(@PathVariable UUID projectId,
                                               @PathVariable int version) {
        return ResponseEntity.ok(planningService.submitBaseline(projectId, version));
    }

    /**
     * Approve a submitted baseline. SPONSOR only.
     * Creates an approval record; approved baseline is immutable.
     */
    @PostMapping("/{version}/approve")
    @PreAuthorize("@projectPerm.hasRole(#projectId, 'SPONSOR', authentication)")
    public ResponseEntity<BaselineSet> approve(@PathVariable UUID projectId,
                                                @PathVariable int version,
                                                @RequestBody(required = false) ApproveRequest body,
                                                Authentication auth) {
        String comment = body != null ? body.getComment() : null;
        return ResponseEntity.ok(planningService.approveBaseline(projectId, version, sub(auth), comment));
    }

    private String sub(Authentication auth) {
        if (auth.getPrincipal() instanceof Jwt jwt) return jwt.getSubject();
        return auth.getName();
    }

    @Data
    static class ApproveRequest {
        private String comment;
    }
}
