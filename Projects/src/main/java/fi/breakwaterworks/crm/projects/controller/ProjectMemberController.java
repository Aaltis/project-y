package fi.breakwaterworks.crm.projects.controller;

import fi.breakwaterworks.crm.projects.model.ProjectRole;
import fi.breakwaterworks.crm.projects.model.ProjectRoleAssignment;
import fi.breakwaterworks.crm.projects.repository.ProjectRoleAssignmentRepository;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import lombok.Data;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.UUID;

@RestController
@RequestMapping("/api/projects/{projectId}/members")
@RequiredArgsConstructor
public class ProjectMemberController {

    private final ProjectRoleAssignmentRepository repository;

    @GetMapping
    @PreAuthorize("@projectPerm.isMember(#projectId, authentication)")
    public List<ProjectRoleAssignment> list(@PathVariable UUID projectId) {
        return repository.findByProjectId(projectId);
    }

    @PostMapping
    @PreAuthorize("@projectPerm.hasRole(#projectId, 'PM', authentication)")
    public ResponseEntity<ProjectRoleAssignment> add(
            @PathVariable UUID projectId,
            @Valid @RequestBody MemberRequest body) {
        ProjectRoleAssignment assignment = new ProjectRoleAssignment();
        assignment.setProjectId(projectId);
        assignment.setUserId(body.getUserId());
        assignment.setRole(body.getRole());
        return ResponseEntity.ok(repository.save(assignment));
    }

    @Data
    static class MemberRequest {
        @NotBlank
        private String userId;
        @NotNull
        private ProjectRole role;
    }
}
