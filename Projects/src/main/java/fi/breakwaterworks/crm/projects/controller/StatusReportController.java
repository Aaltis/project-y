package fi.breakwaterworks.crm.projects.controller;

import fi.breakwaterworks.crm.projects.model.RagStatus;
import fi.breakwaterworks.crm.projects.model.StatusReport;
import fi.breakwaterworks.crm.projects.service.ProjectMonitoringService;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
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
@RequestMapping("/api/projects/{projectId}/status-reports")
@RequiredArgsConstructor
public class StatusReportController {

    private final ProjectMonitoringService monitoringService;

    @GetMapping
    @PreAuthorize("@projectPerm.isMember(#projectId, authentication)")
    public List<StatusReport> list(@PathVariable UUID projectId) {
        return monitoringService.listStatusReports(projectId);
    }

    @PostMapping
    @PreAuthorize("@projectPerm.hasRole(#projectId, 'PM', authentication)")
    public ResponseEntity<StatusReport> create(@PathVariable UUID projectId,
                                                @Valid @RequestBody StatusReportRequest body,
                                                Authentication auth) {
        return ResponseEntity.ok(monitoringService.createStatusReport(
                projectId, body.getPeriodStart(), body.getPeriodEnd(),
                body.getSummary(), body.getRagScope(), body.getRagSchedule(), body.getRagCost(),
                body.getKeyRisks(), body.getKeyIssues(), sub(auth)));
    }

    private String sub(Authentication auth) {
        if (auth.getPrincipal() instanceof Jwt jwt) return jwt.getSubject();
        return auth.getName();
    }

    @Data
    static class StatusReportRequest {
        @NotNull
        private LocalDate periodStart;
        @NotNull
        private LocalDate periodEnd;
        private String summary;
        private RagStatus ragScope;
        private RagStatus ragSchedule;
        private RagStatus ragCost;
        private String keyRisks;
        private String keyIssues;
    }
}
