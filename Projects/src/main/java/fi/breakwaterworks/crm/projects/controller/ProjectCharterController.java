package fi.breakwaterworks.crm.projects.controller;

import fi.breakwaterworks.crm.projects.model.ProjectCharter;
import fi.breakwaterworks.crm.projects.service.ProjectInitiationService;
import lombok.Data;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;

import java.math.BigDecimal;
import java.util.UUID;

@RestController
@RequestMapping("/api/projects/{projectId}/charter")
@RequiredArgsConstructor
public class ProjectCharterController {

    private final ProjectInitiationService initiationService;

    /**
     * Create a charter for a project. Project must be DRAFT.
     * Only the PM of the project may create the charter.
     */
    @PostMapping
    @PreAuthorize("@projectPerm.hasRole(#projectId, 'PM', authentication)")
    public ResponseEntity<ProjectCharter> create(@PathVariable UUID projectId,
                                                  @RequestBody CharterRequest body) {
        ProjectCharter charter = initiationService.createCharter(
                projectId,
                body.getObjectives(),
                body.getHighLevelScope(),
                body.getSuccessCriteria(),
                body.getSummaryBudget(),
                body.getKeyRisks());
        return ResponseEntity.ok(charter);
    }

    /**
     * Submit the charter for sponsor approval. Charter must be DRAFT.
     * Only the PM of the project may submit.
     */
    @PostMapping("/submit")
    @PreAuthorize("@projectPerm.hasRole(#projectId, 'PM', authentication)")
    public ResponseEntity<ProjectCharter> submit(@PathVariable UUID projectId) {
        return ResponseEntity.ok(initiationService.submitCharter(projectId));
    }

    /**
     * Approve the charter. Charter must be SUBMITTED.
     * Only the SPONSOR of the project may approve.
     * Side effects: charter → APPROVED, project → ACTIVE, approval record created.
     */
    @PostMapping("/approve")
    @PreAuthorize("@projectPerm.hasRole(#projectId, 'SPONSOR', authentication)")
    public ResponseEntity<ProjectCharter> approve(@PathVariable UUID projectId,
                                                   @RequestBody(required = false) ApproveRequest body,
                                                   Authentication auth) {
        String comment = body != null ? body.getComment() : null;
        return ResponseEntity.ok(initiationService.approveCharter(projectId, sub(auth), comment));
    }

    private String sub(Authentication auth) {
        if (auth.getPrincipal() instanceof Jwt jwt) return jwt.getSubject();
        return auth.getName();
    }

    @Data
    static class CharterRequest {
        private String objectives;
        private String highLevelScope;
        private String successCriteria;
        private BigDecimal summaryBudget;
        private String keyRisks;
    }

    @Data
    static class ApproveRequest {
        private String comment;
    }
}
