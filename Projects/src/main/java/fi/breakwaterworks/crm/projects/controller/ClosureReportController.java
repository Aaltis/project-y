package fi.breakwaterworks.crm.projects.controller;

import fi.breakwaterworks.crm.projects.model.ClosureReport;
import fi.breakwaterworks.crm.projects.service.ProjectClosingService;
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
@RequestMapping("/api/projects/{projectId}/closure-report")
@RequiredArgsConstructor
public class ClosureReportController {

    private final ProjectClosingService closingService;

    @PostMapping
    @PreAuthorize("@projectPerm.hasRole(#projectId, 'PM', authentication)")
    public ResponseEntity<ClosureReport> create(@PathVariable UUID projectId,
                                                @RequestBody CreateClosureReportRequest body) {
        return ResponseEntity.ok(closingService.createClosureReport(
                projectId, body.getOutcomesSummary(), body.getBudgetActual(),
                body.getScheduleActual(), body.getAcceptanceSummary()));
    }

    @GetMapping
    @PreAuthorize("@projectPerm.isMember(#projectId, authentication)")
    public ResponseEntity<ClosureReport> get(@PathVariable UUID projectId) {
        return ResponseEntity.ok(closingService.getClosureReport(projectId));
    }

    @PostMapping("/submit")
    @PreAuthorize("@projectPerm.hasRole(#projectId, 'PM', authentication)")
    public ResponseEntity<ClosureReport> submit(@PathVariable UUID projectId) {
        return ResponseEntity.ok(closingService.submitClosureReport(projectId));
    }

    @PostMapping("/approve")
    @PreAuthorize("@projectPerm.hasRole(#projectId, 'SPONSOR', authentication)")
    public ResponseEntity<ClosureReport> approve(@PathVariable UUID projectId,
                                                  Authentication auth,
                                                  @RequestBody(required = false) ApproveRequest body) {
        String comment = body != null ? body.getComment() : null;
        return ResponseEntity.ok(closingService.approveClosureReport(projectId, sub(auth), comment));
    }

    private String sub(Authentication auth) {
        if (auth.getPrincipal() instanceof Jwt jwt) return jwt.getSubject();
        return auth.getName();
    }

    @Data
    static class CreateClosureReportRequest {
        private String outcomesSummary;
        private BigDecimal budgetActual;
        private String scheduleActual;
        private String acceptanceSummary;
    }

    @Data
    static class ApproveRequest {
        private String comment;
    }
}
