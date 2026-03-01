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
public class ProjectMonitoringService {

    private final ProjectRepository projectRepository;
    private final ChangeRequestRepository changeRequestRepository;
    private final DecisionLogRepository decisionLogRepository;
    private final StatusReportRepository statusReportRepository;
    private final ApprovalRepository approvalRepository;
    private final ProjectPlanningService planningService;

    // -----------------------------------------------------------------------
    // Change Requests
    // -----------------------------------------------------------------------

    public ChangeRequest createChangeRequest(UUID projectId, ChangeRequestType type,
                                              String description, String impactScope,
                                              Integer impactScheduleDays, BigDecimal impactCost,
                                              String submittedBy) {
        requireProject(projectId);
        ChangeRequest cr = new ChangeRequest();
        cr.setProjectId(projectId);
        cr.setType(type);
        cr.setDescription(description);
        cr.setImpactScope(impactScope);
        cr.setImpactScheduleDays(impactScheduleDays);
        cr.setImpactCost(impactCost);
        cr.setSubmittedBy(submittedBy);
        cr.setStatus(ChangeRequestStatus.DRAFT);
        return changeRequestRepository.save(cr);
    }

    public List<ChangeRequest> listChangeRequests(UUID projectId) {
        requireProject(projectId);
        return changeRequestRepository.findByProjectId(projectId);
    }

    public ChangeRequest getChangeRequest(UUID projectId, UUID crId) {
        return requireChangeRequest(projectId, crId);
    }

    @Transactional
    public ChangeRequest submitChangeRequest(UUID projectId, UUID crId) {
        ChangeRequest cr = requireChangeRequest(projectId, crId);
        if (cr.getStatus() != ChangeRequestStatus.DRAFT) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "CR must be DRAFT to submit (current: " + cr.getStatus() + ")");
        }
        cr.setStatus(ChangeRequestStatus.SUBMITTED);
        return changeRequestRepository.save(cr);
    }

    @Transactional
    public ChangeRequest reviewChangeRequest(UUID projectId, UUID crId) {
        ChangeRequest cr = requireChangeRequest(projectId, crId);
        if (cr.getStatus() != ChangeRequestStatus.SUBMITTED) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "CR must be SUBMITTED to move to review (current: " + cr.getStatus() + ")");
        }
        cr.setStatus(ChangeRequestStatus.IN_REVIEW);
        return changeRequestRepository.save(cr);
    }

    /**
     * Approve a CR that is IN_REVIEW.
     * If the CR type affects SCOPE, SCHEDULE, or COST, a new DRAFT baseline is automatically
     * created and linked to this CR.
     */
    @Transactional
    public ChangeRequest approveChangeRequest(UUID projectId, UUID crId,
                                               String approverId, String comment) {
        ChangeRequest cr = requireChangeRequest(projectId, crId);
        if (cr.getStatus() != ChangeRequestStatus.IN_REVIEW) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "CR must be IN_REVIEW to approve (current: " + cr.getStatus() + ")");
        }
        cr.setStatus(ChangeRequestStatus.APPROVED);
        changeRequestRepository.save(cr);

        Approval approval = new Approval();
        approval.setResourceType(ApprovalResourceType.CHANGE_REQUEST);
        approval.setResourceId(cr.getId());
        approval.setRequestedBy(cr.getSubmittedBy());
        approval.setApproverId(approverId);
        approval.setStatus(ApprovalStatus.APPROVED);
        approval.setComment(comment);
        approvalRepository.save(approval);

        if (cr.getType().requiresNewBaseline()) {
            BaselineSet newBaseline = planningService.createBaseline(projectId, approverId);
            newBaseline.setChangeRequestId(cr.getId());
            // planningService.createBaseline already saved; update the link
            planningService.saveBaseline(newBaseline);
        }

        return cr;
    }

    @Transactional
    public ChangeRequest rejectChangeRequest(UUID projectId, UUID crId,
                                              String approverId, String comment) {
        ChangeRequest cr = requireChangeRequest(projectId, crId);
        if (cr.getStatus() != ChangeRequestStatus.IN_REVIEW) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "CR must be IN_REVIEW to reject (current: " + cr.getStatus() + ")");
        }
        cr.setStatus(ChangeRequestStatus.REJECTED);
        changeRequestRepository.save(cr);

        Approval approval = new Approval();
        approval.setResourceType(ApprovalResourceType.CHANGE_REQUEST);
        approval.setResourceId(cr.getId());
        approval.setRequestedBy(cr.getSubmittedBy());
        approval.setApproverId(approverId);
        approval.setStatus(ApprovalStatus.REJECTED);
        approval.setComment(comment);
        approvalRepository.save(approval);

        return cr;
    }

    /**
     * Mark a CR as IMPLEMENTED. PM only.
     * If the CR has a linked baseline, that baseline must be APPROVED first.
     */
    @Transactional
    public ChangeRequest implementChangeRequest(UUID projectId, UUID crId) {
        ChangeRequest cr = requireChangeRequest(projectId, crId);
        if (cr.getStatus() != ChangeRequestStatus.APPROVED) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "CR must be APPROVED to implement (current: " + cr.getStatus() + ")");
        }
        if (cr.getType().requiresNewBaseline()) {
            boolean linkedBaselineApproved = planningService
                    .listBaselines(projectId)
                    .stream()
                    .anyMatch(b -> cr.getId().equals(b.getChangeRequestId())
                            && b.getStatus() == BaselineStatus.APPROVED);
            if (!linkedBaselineApproved) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                        "The baseline linked to this CR must be APPROVED before implementation");
            }
        }
        cr.setStatus(ChangeRequestStatus.IMPLEMENTED);
        return changeRequestRepository.save(cr);
    }

    // -----------------------------------------------------------------------
    // Decision Log
    // -----------------------------------------------------------------------

    public DecisionLog createDecisionLog(UUID projectId, String decision,
                                          LocalDate decisionDate, String madeBy) {
        requireProject(projectId);
        DecisionLog log = new DecisionLog();
        log.setProjectId(projectId);
        log.setDecision(decision);
        log.setDecisionDate(decisionDate);
        log.setMadeBy(madeBy);
        return decisionLogRepository.save(log);
    }

    public List<DecisionLog> listDecisionLogs(UUID projectId) {
        requireProject(projectId);
        return decisionLogRepository.findByProjectId(projectId);
    }

    // -----------------------------------------------------------------------
    // Status Reports
    // -----------------------------------------------------------------------

    public StatusReport createStatusReport(UUID projectId, LocalDate periodStart,
                                            LocalDate periodEnd, String summary,
                                            RagStatus ragScope, RagStatus ragSchedule,
                                            RagStatus ragCost, String keyRisks,
                                            String keyIssues, String createdBy) {
        requireProject(projectId);
        StatusReport report = new StatusReport();
        report.setProjectId(projectId);
        report.setPeriodStart(periodStart);
        report.setPeriodEnd(periodEnd);
        report.setSummary(summary);
        report.setRagScope(ragScope != null ? ragScope : RagStatus.GREEN);
        report.setRagSchedule(ragSchedule != null ? ragSchedule : RagStatus.GREEN);
        report.setRagCost(ragCost != null ? ragCost : RagStatus.GREEN);
        report.setKeyRisks(keyRisks);
        report.setKeyIssues(keyIssues);
        report.setCreatedBy(createdBy);
        return statusReportRepository.save(report);
    }

    public List<StatusReport> listStatusReports(UUID projectId) {
        requireProject(projectId);
        return statusReportRepository.findByProjectIdOrderByPeriodStartDesc(projectId);
    }

    // -----------------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------------

    private void requireProject(UUID projectId) {
        if (!projectRepository.existsById(projectId)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Project not found");
        }
    }

    private ChangeRequest requireChangeRequest(UUID projectId, UUID crId) {
        ChangeRequest cr = changeRequestRepository.findById(crId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                        "Change request not found"));
        if (!cr.getProjectId().equals(projectId)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Change request not found");
        }
        return cr;
    }
}
