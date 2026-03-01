package fi.breakwaterworks.crm.projects.controller;

import fi.breakwaterworks.crm.projects.model.WorkLog;
import fi.breakwaterworks.crm.projects.service.ProjectExecutionService;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import lombok.Data;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

@RestController
@RequestMapping("/api/projects/{projectId}/work-logs")
@RequiredArgsConstructor
public class WorkLogController {

    private final ProjectExecutionService executionService;

    @GetMapping
    @PreAuthorize("@projectPerm.isMember(#projectId, authentication)")
    public List<WorkLog> list(@PathVariable UUID projectId) {
        return executionService.listWorkLogs(projectId);
    }

    @PostMapping
    @PreAuthorize("@projectPerm.isMember(#projectId, authentication)")
    public ResponseEntity<WorkLog> create(@PathVariable UUID projectId,
                                           @Valid @RequestBody WorkLogRequest body,
                                           Authentication auth) {
        return ResponseEntity.ok(executionService.logWork(
                projectId, body.getTaskId(), sub(auth),
                body.getLogDate(), body.getHours(), body.getNote()));
    }

    private String sub(Authentication auth) {
        if (auth.getPrincipal() instanceof Jwt jwt) return jwt.getSubject();
        return auth.getName();
    }

    @Data
    static class WorkLogRequest {
        @NotNull
        private UUID taskId;
        @NotNull
        private LocalDate logDate;
        @NotNull
        private BigDecimal hours;
        private String note;
    }
}
