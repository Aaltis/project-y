package fi.breakwaterworks.crm.projects.service;

import fi.breakwaterworks.crm.projects.model.*;
import fi.breakwaterworks.crm.projects.repository.*;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.Authentication;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.UUID;

@Service
@RequiredArgsConstructor
public class ProjectInitiationService {

    private final ProjectRepository projectRepository;
    private final ProjectCharterRepository charterRepository;
    private final ApprovalRepository approvalRepository;
    private final ProjectRoleAssignmentRepository roleRepository;

    @Transactional
    public Project createProject(String name, String sponsorId, String pmId,
                                 LocalDate startTarget, LocalDate endTarget) {
        Project project = new Project();
        project.setName(name);
        project.setSponsorId(sponsorId);
        project.setPmId(pmId);
        project.setStartTarget(startTarget);
        project.setEndTarget(endTarget);
        project.setStatus(ProjectStatus.DRAFT);
        project = projectRepository.save(project);

        addRole(project.getId(), pmId, ProjectRole.PM);
        if (!sponsorId.equals(pmId)) {
            addRole(project.getId(), sponsorId, ProjectRole.SPONSOR);
        }
        return project;
    }

    @Transactional
    public ProjectCharter createCharter(UUID projectId, String objectives, String highLevelScope,
                                        String successCriteria, BigDecimal summaryBudget, String keyRisks) {
        requireProject(projectId, ProjectStatus.DRAFT);

        charterRepository.findByProjectId(projectId).ifPresent(existing -> {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "A charter already exists for this project (status: " + existing.getStatus() + ")");
        });

        ProjectCharter charter = new ProjectCharter();
        charter.setProjectId(projectId);
        charter.setObjectives(objectives);
        charter.setHighLevelScope(highLevelScope);
        charter.setSuccessCriteria(successCriteria);
        charter.setSummaryBudget(summaryBudget);
        charter.setKeyRisks(keyRisks);
        charter.setStatus(CharterStatus.DRAFT);
        return charterRepository.save(charter);
    }

    @Transactional
    public ProjectCharter submitCharter(UUID projectId) {
        ProjectCharter charter = requireCharter(projectId);
        if (charter.getStatus() != CharterStatus.DRAFT) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Charter must be in DRAFT to submit (current: " + charter.getStatus() + ")");
        }
        charter.setStatus(CharterStatus.SUBMITTED);
        return charterRepository.save(charter);
    }

    @Transactional
    public ProjectCharter approveCharter(UUID projectId, String approverId, String comment) {
        Project project = requireProject(projectId, null);
        ProjectCharter charter = requireCharter(projectId);

        if (charter.getStatus() != CharterStatus.SUBMITTED) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Charter must be SUBMITTED before approval (current: " + charter.getStatus() + ")");
        }

        charter.setStatus(CharterStatus.APPROVED);
        charterRepository.save(charter);

        Approval approval = new Approval();
        approval.setResourceType(ApprovalResourceType.CHARTER);
        approval.setResourceId(charter.getId());
        approval.setRequestedBy(project.getPmId());
        approval.setApproverId(approverId);
        approval.setStatus(ApprovalStatus.APPROVED);
        approval.setComment(comment);
        approvalRepository.save(approval);

        project.setStatus(ProjectStatus.ACTIVE);
        projectRepository.save(project);

        return charter;
    }

    private Project requireProject(UUID projectId, ProjectStatus requiredStatus) {
        Project project = projectRepository.findById(projectId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Project not found"));
        if (requiredStatus != null && project.getStatus() != requiredStatus) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Project must be " + requiredStatus + " (current: " + project.getStatus() + ")");
        }
        return project;
    }

    private ProjectCharter requireCharter(UUID projectId) {
        return charterRepository.findByProjectId(projectId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                        "No charter found for project " + projectId));
    }

    private void addRole(UUID projectId, String userId, ProjectRole role) {
        if (roleRepository.existsByProjectIdAndUserIdAndRole(projectId, userId, role)) return;
        ProjectRoleAssignment assignment = new ProjectRoleAssignment();
        assignment.setProjectId(projectId);
        assignment.setUserId(userId);
        assignment.setRole(role);
        roleRepository.save(assignment);
    }

    private String sub(Authentication auth) {
        if (auth.getPrincipal() instanceof Jwt jwt) return jwt.getSubject();
        return auth.getName();
    }
}
