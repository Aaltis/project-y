package fi.breakwaterworks.crm.projects.controller;

import fi.breakwaterworks.crm.projects.model.Issue;
import fi.breakwaterworks.crm.projects.model.IssueSeverity;
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

import java.util.List;
import java.util.UUID;

@RestController
@RequestMapping("/api/projects/{projectId}/issues")
@RequiredArgsConstructor
public class IssueController {

    private final ProjectExecutionService executionService;

    @GetMapping
    @PreAuthorize("@projectPerm.isMember(#projectId, authentication)")
    public List<Issue> list(@PathVariable UUID projectId) {
        return executionService.listIssues(projectId);
    }

    @PostMapping
    @PreAuthorize("@projectPerm.isMember(#projectId, authentication)")
    public ResponseEntity<Issue> create(@PathVariable UUID projectId,
                                         @Valid @RequestBody IssueRequest body,
                                         Authentication auth) {
        String ownerId = body.getOwnerId() != null ? body.getOwnerId() : sub(auth);
        return ResponseEntity.ok(executionService.createIssue(
                projectId, body.getTitle(), body.getSeverity(), ownerId));
    }

    private String sub(Authentication auth) {
        if (auth.getPrincipal() instanceof Jwt jwt) return jwt.getSubject();
        return auth.getName();
    }

    @Data
    static class IssueRequest {
        @NotBlank
        private String title;
        private IssueSeverity severity;
        private String ownerId;
    }
}
