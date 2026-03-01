package fi.breakwaterworks.crm.projects.service;

import fi.breakwaterworks.crm.projects.model.ProjectRole;
import fi.breakwaterworks.crm.projects.repository.ProjectRoleAssignmentRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.Authentication;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.stereotype.Service;

import java.util.UUID;

/**
 * Project-level permission checks.
 *
 * Usage in controllers:
 *   {@code @PreAuthorize("@projectPerm.hasRole(#projectId, 'PM', authentication)")}
 *   {@code @PreAuthorize("@projectPerm.isMember(#projectId, authentication)")}
 *
 * crm_admin bypasses all project role checks.
 * crm_sales must have an explicit assignment in project_role_assignment.
 */
@Service("projectPerm")
@RequiredArgsConstructor
public class ProjectPermissionService {

    private final ProjectRoleAssignmentRepository repository;

    public boolean hasRole(UUID projectId, String role, Authentication auth) {
        if (isAdmin(auth)) return true;
        return repository.existsByProjectIdAndUserIdAndRole(projectId, sub(auth), ProjectRole.valueOf(role));
    }

    public boolean isMember(UUID projectId, Authentication auth) {
        if (isAdmin(auth)) return true;
        return repository.existsByProjectIdAndUserId(projectId, sub(auth));
    }

    public boolean canApproveDeliverable(UUID projectId, Authentication auth) {
        if (isAdmin(auth)) return true;
        String sub = sub(auth);
        return repository.existsByProjectIdAndUserIdAndRole(projectId, sub, ProjectRole.SPONSOR)
                || repository.existsByProjectIdAndUserIdAndRole(projectId, sub, ProjectRole.QA);
    }

    public boolean canApproveChangeRequest(UUID projectId, Authentication auth) {
        if (isAdmin(auth)) return true;
        String sub = sub(auth);
        return repository.existsByProjectIdAndUserIdAndRole(projectId, sub, ProjectRole.SPONSOR)
                || repository.existsByProjectIdAndUserIdAndRole(projectId, sub, ProjectRole.PM);
    }

    private boolean isAdmin(Authentication auth) {
        return auth.getAuthorities().stream()
                .anyMatch(a -> a.getAuthority().equals("ROLE_crm_admin"));
    }

    private String sub(Authentication auth) {
        if (auth.getPrincipal() instanceof Jwt jwt) {
            return jwt.getSubject();
        }
        return auth.getName();
    }
}
