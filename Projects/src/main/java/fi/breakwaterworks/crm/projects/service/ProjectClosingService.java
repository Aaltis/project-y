package fi.breakwaterworks.crm.projects.service;

import fi.breakwaterworks.crm.projects.model.*;
import fi.breakwaterworks.crm.projects.repository.*;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;
import java.util.List;
import java.util.UUID;

@Service
@RequiredArgsConstructor
public class ProjectClosingService {

    private final ProjectRepository projectRepository;
    private final ClosureReportRepository closureReportRepository;
    private final LessonsLearnedRepository lessonsLearnedRepository;
    private final ApprovalRepository approvalRepository;
    private final DeliverableRepository deliverableRepository;

    // -----------------------------------------------------------------------
    // Closure Report
    // -----------------------------------------------------------------------

    @Transactional
    public ClosureReport createClosureReport(UUID projectId, String outcomesSummary,
                                              BigDecimal budgetActual, String scheduleActual,
                                              String acceptanceSummary) {
        requireActiveProject(projectId);
        if (closureReportRepository.findByProjectId(projectId).isPresent()) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "A closure report already exists for this project");
        }
        ClosureReport report = new ClosureReport();
        report.setProjectId(projectId);
        report.setOutcomesSummary(outcomesSummary);
        report.setBudgetActual(budgetActual);
        report.setScheduleActual(scheduleActual);
        report.setAcceptanceSummary(acceptanceSummary);
        report.setStatus(ClosureReportStatus.DRAFT);
        return closureReportRepository.save(report);
    }

    public ClosureReport getClosureReport(UUID projectId) {
        requireProject(projectId);
        return closureReportRepository.findByProjectId(projectId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                        "No closure report found for this project"));
    }

    @Transactional
    public ClosureReport submitClosureReport(UUID projectId) {
        ClosureReport report = requireClosureReport(projectId);
        if (report.getStatus() != ClosureReportStatus.DRAFT) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Closure report must be DRAFT to submit (current: " + report.getStatus() + ")");
        }
        report.setStatus(ClosureReportStatus.SUBMITTED);
        return closureReportRepository.save(report);
    }

    @Transactional
    public ClosureReport approveClosureReport(UUID projectId, String approverId, String comment) {
        ClosureReport report = requireClosureReport(projectId);
        if (report.getStatus() != ClosureReportStatus.SUBMITTED) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Closure report must be SUBMITTED to approve (current: " + report.getStatus() + ")");
        }
        report.setStatus(ClosureReportStatus.APPROVED);
        closureReportRepository.save(report);

        Approval approval = new Approval();
        approval.setResourceType(ApprovalResourceType.CLOSURE);
        approval.setResourceId(report.getId());
        approval.setRequestedBy(approverId);
        approval.setApproverId(approverId);
        approval.setStatus(ApprovalStatus.APPROVED);
        approval.setComment(comment);
        approvalRepository.save(approval);

        return report;
    }

    // -----------------------------------------------------------------------
    // Lessons Learned
    // -----------------------------------------------------------------------

    public LessonsLearned addLesson(UUID projectId, String category,
                                    String whatHappened, String recommendation,
                                    String createdBy) {
        requireProject(projectId);
        LessonsLearned lesson = new LessonsLearned();
        lesson.setProjectId(projectId);
        lesson.setCategory(category);
        lesson.setWhatHappened(whatHappened);
        lesson.setRecommendation(recommendation);
        lesson.setCreatedBy(createdBy);
        return lessonsLearnedRepository.save(lesson);
    }

    public List<LessonsLearned> listLessons(UUID projectId) {
        requireProject(projectId);
        return lessonsLearnedRepository.findByProjectIdOrderByCreatedAtDesc(projectId);
    }

    // -----------------------------------------------------------------------
    // Close Project — gate check
    // -----------------------------------------------------------------------

    /**
     * Attempt to close the project.
     *
     * Gate conditions:
     * 1. Project must be ACTIVE.
     * 2. Closure report must exist and be APPROVED (Sponsor approval serves as
     *    acceptance of deliverable state, including any explicitly noted waivers).
     * 3. All deliverables must be ACCEPTED (not PLANNED, SUBMITTED, or REJECTED).
     *
     * If all conditions pass, project.status → CLOSED.
     */
    @Transactional
    public Project closeProject(UUID projectId) {
        Project project = requireActiveProject(projectId);

        ClosureReport report = closureReportRepository.findByProjectId(projectId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.BAD_REQUEST,
                        "Cannot close project: no closure report found"));
        if (report.getStatus() != ClosureReportStatus.APPROVED) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Cannot close project: closure report must be APPROVED (current: "
                            + report.getStatus() + ")");
        }

        List<Deliverable> deliverables = deliverableRepository.findByProjectId(projectId);
        List<Deliverable> notAccepted = deliverables.stream()
                .filter(d -> d.getStatus() != DeliverableStatus.ACCEPTED)
                .toList();
        if (!notAccepted.isEmpty()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Cannot close project: " + notAccepted.size()
                            + " deliverable(s) not yet ACCEPTED. Note waivers in closure report acceptance_summary first.");
        }

        project.setStatus(ProjectStatus.CLOSED);
        return projectRepository.save(project);
    }

    // -----------------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------------

    private void requireProject(UUID projectId) {
        if (!projectRepository.existsById(projectId)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Project not found");
        }
    }

    private Project requireActiveProject(UUID projectId) {
        Project project = projectRepository.findById(projectId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Project not found"));
        if (project.getStatus() != ProjectStatus.ACTIVE) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Project must be ACTIVE (current: " + project.getStatus() + ")");
        }
        return project;
    }

    private ClosureReport requireClosureReport(UUID projectId) {
        requireProject(projectId);
        return closureReportRepository.findByProjectId(projectId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                        "No closure report found for this project"));
    }
}
