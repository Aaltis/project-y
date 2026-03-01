package fi.breakwaterworks.crm.projects.controller;

import fi.breakwaterworks.crm.projects.model.ChangeRequest;
import fi.breakwaterworks.crm.projects.model.ChangeRequestType;
import fi.breakwaterworks.crm.projects.service.ProjectMonitoringService;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import lombok.Data;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;

import java.math.BigDecimal;
import java.util.List;
import java.util.UUID;

@RestController
@RequestMapping("/api/projects/{projectId}/change-requests")
@RequiredArgsConstructor
public class ChangeRequestController {

    private final ProjectMonitoringService monitoringService;

    @GetMapping
    @PreAuthorize("@projectPerm.isMember(#projectId, authentication)")
    public List<ChangeRequest> list(@PathVariable UUID projectId) {
        return monitoringService.listChangeRequests(projectId);
    }

    @GetMapping("/{crId}")
    @PreAuthorize("@projectPerm.isMember(#projectId, authentication)")
    public ChangeRequest get(@PathVariable UUID projectId, @PathVariable UUID crId) {
        return monitoringService.getChangeRequest(projectId, crId);
    }

    @PostMapping
    @PreAuthorize("@projectPerm.isMember(#projectId, authentication)")
    public ResponseEntity<ChangeRequest> create(@PathVariable UUID projectId,
                                                 @Valid @RequestBody ChangeRequestBody body,
                                                 Authentication auth) {
        return ResponseEntity.ok(monitoringService.createChangeRequest(
                projectId, body.getType(), body.getDescription(),
                body.getImpactScope(), body.getImpactScheduleDays(), body.getImpactCost(),
                sub(auth)));
    }

    @PostMapping("/{crId}/submit")
    @PreAuthorize("@projectPerm.isMember(#projectId, authentication)")
    public ResponseEntity<ChangeRequest> submit(@PathVariable UUID projectId,
                                                 @PathVariable UUID crId) {
        return ResponseEntity.ok(monitoringService.submitChangeRequest(projectId, crId));
    }

    @PostMapping("/{crId}/review")
    @PreAuthorize("@projectPerm.hasRole(#projectId, 'PM', authentication)")
    public ResponseEntity<ChangeRequest> review(@PathVariable UUID projectId,
                                                 @PathVariable UUID crId) {
        return ResponseEntity.ok(monitoringService.reviewChangeRequest(projectId, crId));
    }

    @PostMapping("/{crId}/approve")
    @PreAuthorize("@projectPerm.canApproveChangeRequest(#projectId, authentication)")
    public ResponseEntity<ChangeRequest> approve(@PathVariable UUID projectId,
                                                  @PathVariable UUID crId,
                                                  @RequestBody(required = false) ReviewBody body,
                                                  Authentication auth) {
        String comment = body != null ? body.getComment() : null;
        return ResponseEntity.ok(monitoringService.approveChangeRequest(projectId, crId, sub(auth), comment));
    }

    @PostMapping("/{crId}/reject")
    @PreAuthorize("@projectPerm.canApproveChangeRequest(#projectId, authentication)")
    public ResponseEntity<ChangeRequest> reject(@PathVariable UUID projectId,
                                                 @PathVariable UUID crId,
                                                 @RequestBody(required = false) ReviewBody body,
                                                 Authentication auth) {
        String comment = body != null ? body.getComment() : null;
        return ResponseEntity.ok(monitoringService.rejectChangeRequest(projectId, crId, sub(auth), comment));
    }

    @PostMapping("/{crId}/implement")
    @PreAuthorize("@projectPerm.hasRole(#projectId, 'PM', authentication)")
    public ResponseEntity<ChangeRequest> implement(@PathVariable UUID projectId,
                                                    @PathVariable UUID crId) {
        return ResponseEntity.ok(monitoringService.implementChangeRequest(projectId, crId));
    }

    private String sub(Authentication auth) {
        if (auth.getPrincipal() instanceof Jwt jwt) return jwt.getSubject();
        return auth.getName();
    }

    @Data
    static class ChangeRequestBody {
        @NotNull
        private ChangeRequestType type;
        @NotBlank
        private String description;
        private String impactScope;
        private Integer impactScheduleDays;
        private BigDecimal impactCost;
    }

    @Data
    static class ReviewBody {
        private String comment;
    }
}
