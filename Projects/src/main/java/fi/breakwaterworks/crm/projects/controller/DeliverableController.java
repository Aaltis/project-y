package fi.breakwaterworks.crm.projects.controller;

import fi.breakwaterworks.crm.projects.model.Deliverable;
import fi.breakwaterworks.crm.projects.service.ProjectExecutionService;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import lombok.Data;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

@RestController
@RequestMapping("/api/projects/{projectId}/deliverables")
@RequiredArgsConstructor
public class DeliverableController {

    private final ProjectExecutionService executionService;

    @GetMapping
    @PreAuthorize("@projectPerm.isMember(#projectId, authentication)")
    public List<Deliverable> list(@PathVariable UUID projectId) {
        return executionService.listDeliverables(projectId);
    }

    @PostMapping
    @PreAuthorize("@projectPerm.hasRole(#projectId, 'PM', authentication)")
    public ResponseEntity<Deliverable> create(@PathVariable UUID projectId,
                                               @Valid @RequestBody DeliverableRequest body) {
        return ResponseEntity.ok(executionService.createDeliverable(
                projectId, body.getName(), body.getDueDate(), body.getAcceptanceCriteria()));
    }

    /**
     * Submit a deliverable for acceptance review. Any project member (TEAM_MEMBER) may submit.
     */
    @PostMapping("/{deliverableId}/submit")
    @PreAuthorize("@projectPerm.isMember(#projectId, authentication)")
    public ResponseEntity<Deliverable> submit(@PathVariable UUID projectId,
                                               @PathVariable UUID deliverableId,
                                               Authentication auth) {
        return ResponseEntity.ok(executionService.submitDeliverable(projectId, deliverableId, sub(auth)));
    }

    /**
     * Accept a submitted deliverable. SPONSOR or QA role required.
     * Creates an approval record (resource_type=DELIVERABLE, status=APPROVED).
     */
    @PostMapping("/{deliverableId}/accept")
    @PreAuthorize("@projectPerm.canApproveDeliverable(#projectId, authentication)")
    public ResponseEntity<Deliverable> accept(@PathVariable UUID projectId,
                                               @PathVariable UUID deliverableId,
                                               @RequestBody(required = false) ReviewRequest body,
                                               Authentication auth) {
        String comment = body != null ? body.getComment() : null;
        return ResponseEntity.ok(executionService.acceptDeliverable(projectId, deliverableId, sub(auth), comment));
    }

    /**
     * Reject a submitted deliverable. SPONSOR or QA role required.
     * Creates an approval record (resource_type=DELIVERABLE, status=REJECTED).
     */
    @PostMapping("/{deliverableId}/reject")
    @PreAuthorize("@projectPerm.canApproveDeliverable(#projectId, authentication)")
    public ResponseEntity<Deliverable> reject(@PathVariable UUID projectId,
                                               @PathVariable UUID deliverableId,
                                               @RequestBody(required = false) ReviewRequest body,
                                               Authentication auth) {
        String comment = body != null ? body.getComment() : null;
        return ResponseEntity.ok(executionService.rejectDeliverable(projectId, deliverableId, sub(auth), comment));
    }

    private String sub(Authentication auth) {
        if (auth.getPrincipal() instanceof Jwt jwt) return jwt.getSubject();
        return auth.getName();
    }

    @Data
    static class DeliverableRequest {
        @NotBlank
        private String name;
        private LocalDate dueDate;
        private String acceptanceCriteria;
    }

    @Data
    static class ReviewRequest {
        private String comment;
    }
}
