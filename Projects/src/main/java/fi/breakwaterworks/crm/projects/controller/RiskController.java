package fi.breakwaterworks.crm.projects.controller;

import fi.breakwaterworks.crm.projects.model.Risk;
import fi.breakwaterworks.crm.projects.service.ProjectPlanningService;
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
@RequestMapping("/api/projects/{projectId}/risks")
@RequiredArgsConstructor
public class RiskController {

    private final ProjectPlanningService planningService;

    @GetMapping
    @PreAuthorize("@projectPerm.isMember(#projectId, authentication)")
    public List<Risk> list(@PathVariable UUID projectId) {
        return planningService.listRisks(projectId);
    }

    @PostMapping
    @PreAuthorize("@projectPerm.isMember(#projectId, authentication)")
    public ResponseEntity<Risk> create(@PathVariable UUID projectId,
                                        @Valid @RequestBody RiskRequest body,
                                        Authentication auth) {
        String ownerId = body.getOwnerId() != null ? body.getOwnerId() : sub(auth);
        return ResponseEntity.ok(planningService.addRisk(
                projectId, body.getDescription(), body.getProbability(),
                body.getImpact(), body.getResponse(), ownerId));
    }

    private String sub(Authentication auth) {
        if (auth.getPrincipal() instanceof Jwt jwt) return jwt.getSubject();
        return auth.getName();
    }

    @Data
    static class RiskRequest {
        @NotBlank
        private String description;
        private String probability;
        private String impact;
        private String response;
        private String ownerId;
    }
}
