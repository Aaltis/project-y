package fi.breakwaterworks.crm.projects.service;

import fi.breakwaterworks.crm.projects.model.*;
import fi.breakwaterworks.crm.projects.repository.*;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

@Service
@RequiredArgsConstructor
public class ProjectExecutionService {

    private final ProjectRepository projectRepository;
    private final DeliverableRepository deliverableRepository;
    private final WorkLogRepository workLogRepository;
    private final IssueRepository issueRepository;
    private final ApprovalRepository approvalRepository;
    private final ScheduleTaskRepository scheduleTaskRepository;

    // -----------------------------------------------------------------------
    // Deliverables
    // -----------------------------------------------------------------------
    public Deliverable createDeliverable(UUID projectId, String name, LocalDate dueDate,
                                          String acceptanceCriteria) {
        requireProject(projectId);
        Deliverable d = new Deliverable();
        d.setProjectId(projectId);
        d.setName(name);
        d.setDueDate(dueDate);
        d.setAcceptanceCriteria(acceptanceCriteria);
        d.setStatus(DeliverableStatus.PLANNED);
        return deliverableRepository.save(d);
    }

    public List<Deliverable> listDeliverables(UUID projectId) {
        requireProject(projectId);
        return deliverableRepository.findByProjectId(projectId);
    }

    @Transactional
    public Deliverable submitDeliverable(UUID projectId, UUID deliverableId, String submittedBy) {
        Deliverable d = requireDeliverable(projectId, deliverableId);
        if (d.getStatus() != DeliverableStatus.PLANNED) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Deliverable must be PLANNED to submit (current: " + d.getStatus() + ")");
        }
        d.setStatus(DeliverableStatus.SUBMITTED);
        d.setSubmittedBy(submittedBy);
        return deliverableRepository.save(d);
    }

    @Transactional
    public Deliverable acceptDeliverable(UUID projectId, UUID deliverableId,
                                          String approverId, String comment) {
        return resolveDeliverable(projectId, deliverableId, approverId, comment,
                DeliverableStatus.ACCEPTED, ApprovalStatus.APPROVED);
    }

    @Transactional
    public Deliverable rejectDeliverable(UUID projectId, UUID deliverableId,
                                          String approverId, String comment) {
        return resolveDeliverable(projectId, deliverableId, approverId, comment,
                DeliverableStatus.REJECTED, ApprovalStatus.REJECTED);
    }

    private Deliverable resolveDeliverable(UUID projectId, UUID deliverableId, String approverId,
                                            String comment, DeliverableStatus newStatus,
                                            ApprovalStatus approvalStatus) {
        Deliverable d = requireDeliverable(projectId, deliverableId);
        if (d.getStatus() != DeliverableStatus.SUBMITTED) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Deliverable must be SUBMITTED (current: " + d.getStatus() + ")");
        }
        d.setStatus(newStatus);
        deliverableRepository.save(d);

        Approval approval = new Approval();
        approval.setResourceType(ApprovalResourceType.DELIVERABLE);
        approval.setResourceId(d.getId());
        approval.setRequestedBy(d.getSubmittedBy());
        approval.setApproverId(approverId);
        approval.setStatus(approvalStatus);
        approval.setComment(comment);
        approvalRepository.save(approval);

        return d;
    }

    // -----------------------------------------------------------------------
    // Work logs
    // -----------------------------------------------------------------------
    public WorkLog logWork(UUID projectId, UUID taskId, String userId,
                            LocalDate logDate, BigDecimal hours, String note) {
        ScheduleTask task = scheduleTaskRepository.findById(taskId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Task not found"));
        if (!task.getProjectId().equals(projectId)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Task not found");
        }
        WorkLog log = new WorkLog();
        log.setTaskId(taskId);
        log.setUserId(userId);
        log.setLogDate(logDate);
        log.setHours(hours);
        log.setNote(note);
        return workLogRepository.save(log);
    }

    public List<WorkLog> listWorkLogs(UUID projectId) {
        requireProject(projectId);
        return workLogRepository.findByProjectId(projectId);
    }

    // -----------------------------------------------------------------------
    // Issues
    // -----------------------------------------------------------------------
    public Issue createIssue(UUID projectId, String title, IssueSeverity severity, String ownerId) {
        requireProject(projectId);
        Issue issue = new Issue();
        issue.setProjectId(projectId);
        issue.setTitle(title);
        issue.setSeverity(severity != null ? severity : IssueSeverity.MEDIUM);
        issue.setOwnerId(ownerId);
        issue.setStatus(IssueStatus.OPEN);
        return issueRepository.save(issue);
    }

    public List<Issue> listIssues(UUID projectId) {
        requireProject(projectId);
        return issueRepository.findByProjectId(projectId);
    }

    // -----------------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------------
    private void requireProject(UUID projectId) {
        if (!projectRepository.existsById(projectId)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Project not found");
        }
    }

    private Deliverable requireDeliverable(UUID projectId, UUID deliverableId) {
        Deliverable d = deliverableRepository.findById(deliverableId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Deliverable not found"));
        if (!d.getProjectId().equals(projectId)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Deliverable not found");
        }
        return d;
    }
}
