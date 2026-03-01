package fi.breakwaterworks.crm.projects.controller;

import fi.breakwaterworks.crm.projects.model.Project;
import fi.breakwaterworks.crm.projects.repository.ProjectRepository;
import fi.breakwaterworks.crm.projects.service.ProjectInitiationService;
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
import java.util.UUID;

@RestController
@RequestMapping("/api/projects")
@RequiredArgsConstructor
public class ProjectController {

    private final ProjectRepository projectRepository;
    private final ProjectInitiationService initiationService;

    /**
     * Create a new project. The caller becomes PM automatically.
     * sponsorId must be the Keycloak sub of the intended sponsor.
     */
    @PostMapping
    public ResponseEntity<Project> create(@Valid @RequestBody CreateProjectRequest body,
                                          Authentication auth) {
        String pmId = sub(auth);
        Project project = initiationService.createProject(
                body.getName(), body.getSponsorId(), pmId,
                body.getStartTarget(), body.getEndTarget());
        return ResponseEntity.ok(project);
    }

    @GetMapping("/{id}")
    @PreAuthorize("@projectPerm.isMember(#id, authentication)")
    public ResponseEntity<Project> get(@PathVariable UUID id) {
        return projectRepository.findById(id)
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }

    private String sub(Authentication auth) {
        if (auth.getPrincipal() instanceof Jwt jwt) return jwt.getSubject();
        return auth.getName();
    }

    @Data
    static class CreateProjectRequest {
        @NotBlank
        private String name;
        @NotNull
        private String sponsorId;
        private LocalDate startTarget;
        private LocalDate endTarget;
    }
}
