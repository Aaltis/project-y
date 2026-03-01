package fi.breakwaterworks.crm.projects.controller;

import fi.breakwaterworks.crm.projects.model.ScheduleTask;
import fi.breakwaterworks.crm.projects.model.TaskStatus;
import fi.breakwaterworks.crm.projects.service.ProjectPlanningService;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import lombok.Data;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

@RestController
@RequestMapping("/api/projects/{projectId}/tasks")
@RequiredArgsConstructor
public class ScheduleTaskController {

    private final ProjectPlanningService planningService;

    @GetMapping
    @PreAuthorize("@projectPerm.isMember(#projectId, authentication)")
    public List<ScheduleTask> list(@PathVariable UUID projectId) {
        return planningService.listTasks(projectId);
    }

    @PostMapping
    @PreAuthorize("@projectPerm.hasRole(#projectId, 'PM', authentication)")
    public ResponseEntity<ScheduleTask> create(@PathVariable UUID projectId,
                                                @Valid @RequestBody TaskRequest body) {
        return ResponseEntity.ok(planningService.addTask(
                projectId, body.getName(), body.getWbsItemId(),
                body.getStartDate(), body.getEndDate(), body.getAssigneeId()));
    }

    @PatchMapping("/{taskId}")
    @PreAuthorize("@projectPerm.isMember(#projectId, authentication)")
    public ResponseEntity<ScheduleTask> updateStatus(@PathVariable UUID projectId,
                                                      @PathVariable UUID taskId,
                                                      @RequestBody StatusRequest body) {
        return ResponseEntity.ok(planningService.updateTaskStatus(projectId, taskId, body.getStatus()));
    }

    @Data
    static class TaskRequest {
        @NotBlank
        private String name;
        private UUID wbsItemId;
        private LocalDate startDate;
        private LocalDate endDate;
        private String assigneeId;
    }

    @Data
    static class StatusRequest {
        @NotNull
        private TaskStatus status;
    }
}
