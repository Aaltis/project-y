package fi.breakwaterworks.crm.projects.controller;

import fi.breakwaterworks.crm.projects.model.DecisionLog;
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

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

@RestController
@RequestMapping("/api/projects/{projectId}/decisions")
@RequiredArgsConstructor
public class DecisionLogController {

    private final ProjectMonitoringService monitoringService;

    @GetMapping
    @PreAuthorize("@projectPerm.isMember(#projectId, authentication)")
    public List<DecisionLog> list(@PathVariable UUID projectId) {
        return monitoringService.listDecisionLogs(projectId);
    }

    @PostMapping
    @PreAuthorize("@projectPerm.hasRole(#projectId, 'PM', authentication)")
    public ResponseEntity<DecisionLog> create(@PathVariable UUID projectId,
                                               @Valid @RequestBody DecisionLogRequest body,
                                               Authentication auth) {
        return ResponseEntity.ok(monitoringService.createDecisionLog(
                projectId, body.getDecision(), body.getDecisionDate(), sub(auth)));
    }

    private String sub(Authentication auth) {
        if (auth.getPrincipal() instanceof Jwt jwt) return jwt.getSubject();
        return auth.getName();
    }

    @Data
    static class DecisionLogRequest {
        @NotBlank
        private String decision;
        @NotNull
        private LocalDate decisionDate;
    }
}
