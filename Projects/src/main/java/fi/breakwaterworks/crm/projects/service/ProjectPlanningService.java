package fi.breakwaterworks.crm.projects.service;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
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
public class ProjectPlanningService {

    private final ProjectRepository projectRepository;
    private final WbsItemRepository wbsItemRepository;
    private final ScheduleTaskRepository scheduleTaskRepository;
    private final CostItemRepository costItemRepository;
    private final RiskRepository riskRepository;
    private final BaselineSetRepository baselineSetRepository;
    private final ApprovalRepository approvalRepository;
    private final ObjectMapper objectMapper;

    // -----------------------------------------------------------------------
    // WBS
    // -----------------------------------------------------------------------
    public WbsItem addWbsItem(UUID projectId, String name, String description,
                               String wbsCode, UUID parentId) {
        requireProject(projectId);
        WbsItem item = new WbsItem();
        item.setProjectId(projectId);
        item.setName(name);
        item.setDescription(description);
        item.setWbsCode(wbsCode);
        item.setParentId(parentId);
        return wbsItemRepository.save(item);
    }

    public List<WbsItem> listWbs(UUID projectId) {
        requireProject(projectId);
        return wbsItemRepository.findByProjectId(projectId);
    }

    // -----------------------------------------------------------------------
    // Tasks
    // -----------------------------------------------------------------------
    public ScheduleTask addTask(UUID projectId, String name, UUID wbsItemId,
                                 LocalDate startDate, LocalDate endDate, String assigneeId) {
        requireProject(projectId);
        ScheduleTask task = new ScheduleTask();
        task.setProjectId(projectId);
        task.setName(name);
        task.setWbsItemId(wbsItemId);
        task.setStartDate(startDate);
        task.setEndDate(endDate);
        task.setAssigneeId(assigneeId);
        task.setStatus(TaskStatus.TODO);
        return scheduleTaskRepository.save(task);
    }

    public List<ScheduleTask> listTasks(UUID projectId) {
        requireProject(projectId);
        return scheduleTaskRepository.findByProjectId(projectId);
    }

    // -----------------------------------------------------------------------
    // Cost items
    // -----------------------------------------------------------------------
    public CostItem addCostItem(UUID projectId, UUID wbsItemId, String category,
                                 BigDecimal plannedCost) {
        requireProject(projectId);
        CostItem item = new CostItem();
        item.setProjectId(projectId);
        item.setWbsItemId(wbsItemId);
        item.setCategory(category);
        item.setPlannedCost(plannedCost);
        return costItemRepository.save(item);
    }

    public List<CostItem> listCostItems(UUID projectId) {
        requireProject(projectId);
        return costItemRepository.findByProjectId(projectId);
    }

    // -----------------------------------------------------------------------
    // Risks
    // -----------------------------------------------------------------------
    public Risk addRisk(UUID projectId, String description, String probability,
                         String impact, String response, String ownerId) {
        requireProject(projectId);
        Risk risk = new Risk();
        risk.setProjectId(projectId);
        risk.setDescription(description);
        risk.setProbability(probability);
        risk.setImpact(impact);
        risk.setResponse(response);
        risk.setOwnerId(ownerId);
        risk.setStatus(RiskStatus.OPEN);
        return riskRepository.save(risk);
    }

    public List<Risk> listRisks(UUID projectId) {
        requireProject(projectId);
        return riskRepository.findByProjectId(projectId);
    }

    // -----------------------------------------------------------------------
    // Baselines
    // -----------------------------------------------------------------------
    @Transactional
    public BaselineSet createBaseline(UUID projectId, String createdBy) {
        requireActiveProject(projectId);

        int nextVersion = baselineSetRepository.findMaxVersionByProjectId(projectId)
                .orElse(0) + 1;

        List<WbsItem> wbsItems = wbsItemRepository.findByProjectId(projectId);
        List<ScheduleTask> tasks = scheduleTaskRepository.findByProjectId(projectId);
        List<CostItem> costItems = costItemRepository.findByProjectId(projectId);

        BaselineSet baseline = new BaselineSet();
        baseline.setProjectId(projectId);
        baseline.setVersion(nextVersion);
        baseline.setScopeSnapshot(toJson(wbsItems));
        baseline.setScheduleSnapshot(toJson(tasks));
        baseline.setCostSnapshot(toJson(costItems));
        baseline.setStatus(BaselineStatus.DRAFT);
        baseline.setCreatedBy(createdBy);
        return baselineSetRepository.save(baseline);
    }

    public List<BaselineSet> listBaselines(UUID projectId) {
        requireProject(projectId);
        return baselineSetRepository.findByProjectId(projectId);
    }

    @Transactional
    public BaselineSet submitBaseline(UUID projectId, int version) {
        BaselineSet baseline = requireBaseline(projectId, version);
        if (baseline.getStatus() != BaselineStatus.DRAFT) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Baseline v" + version + " must be DRAFT to submit (current: " + baseline.getStatus() + ")");
        }
        baseline.setStatus(BaselineStatus.SUBMITTED);
        return baselineSetRepository.save(baseline);
    }

    @Transactional
    public BaselineSet approveBaseline(UUID projectId, int version, String approverId, String comment) {
        Project project = requireProject(projectId);
        BaselineSet baseline = requireBaseline(projectId, version);
        if (baseline.getStatus() != BaselineStatus.SUBMITTED) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Baseline v" + version + " must be SUBMITTED before approval (current: " + baseline.getStatus() + ")");
        }

        baseline.setStatus(BaselineStatus.APPROVED);
        baselineSetRepository.save(baseline);

        Approval approval = new Approval();
        approval.setResourceType(ApprovalResourceType.BASELINE);
        approval.setResourceId(baseline.getId());
        approval.setRequestedBy(project.getPmId());
        approval.setApproverId(approverId);
        approval.setStatus(ApprovalStatus.APPROVED);
        approval.setComment(comment);
        approvalRepository.save(approval);

        return baseline;
    }

    // -----------------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------------
    private Project requireProject(UUID projectId) {
        return projectRepository.findById(projectId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Project not found"));
    }

    private Project requireActiveProject(UUID projectId) {
        Project p = requireProject(projectId);
        if (p.getStatus() != ProjectStatus.ACTIVE) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Project must be ACTIVE to create a baseline (current: " + p.getStatus() + ")");
        }
        return p;
    }

    private BaselineSet requireBaseline(UUID projectId, int version) {
        return baselineSetRepository.findByProjectIdAndVersion(projectId, version)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                        "Baseline v" + version + " not found for project " + projectId));
    }

    /** Exposed for linking a baseline to a change request after creation. */
    public BaselineSet saveBaseline(BaselineSet baseline) {
        return baselineSetRepository.save(baseline);
    }

    public ScheduleTask updateTaskStatus(UUID projectId, UUID taskId, TaskStatus status) {
        ScheduleTask task = scheduleTaskRepository.findById(taskId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Task not found"));
        if (!task.getProjectId().equals(projectId)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Task not found");
        }
        task.setStatus(status);
        return scheduleTaskRepository.save(task);
    }

    private String toJson(Object obj) {
        try {
            return objectMapper.writeValueAsString(obj);
        } catch (JsonProcessingException e) {
            throw new ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR,
                    "Failed to serialize snapshot: " + e.getMessage());
        }
    }
}
