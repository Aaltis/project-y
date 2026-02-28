package fi.breakwaterworks.crm.activities.controller;

import fi.breakwaterworks.crm.activities.model.Activity;
import fi.breakwaterworks.crm.activities.repository.ActivityRepository;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.UUID;

@RestController
@RequestMapping("/api/opportunities/{opportunityId}/activities")
@RequiredArgsConstructor
public class ActivityController {

    private final ActivityRepository activityRepository;

    @GetMapping
    public List<Activity> list(@PathVariable UUID opportunityId) {
        return activityRepository.findByOpportunityIdOrderByCreatedAtDesc(opportunityId);
    }

    @PostMapping
    public ResponseEntity<Activity> create(@PathVariable UUID opportunityId,
                                           @Valid @RequestBody Activity activity,
                                           Authentication auth) {
        activity.setOpportunityId(opportunityId);
        activity.setCreatedBy(sub(auth));
        return ResponseEntity.ok(activityRepository.save(activity));
    }

    @GetMapping("/{id}")
    public ResponseEntity<Activity> get(@PathVariable UUID opportunityId, @PathVariable UUID id) {
        return activityRepository.findById(id)
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Void> delete(@PathVariable UUID opportunityId, @PathVariable UUID id) {
        if (!activityRepository.existsById(id)) return ResponseEntity.notFound().build();
        activityRepository.deleteById(id);
        return ResponseEntity.noContent().build();
    }

    private String sub(Authentication auth) {
        if (auth.getPrincipal() instanceof Jwt jwt) {
            return jwt.getSubject();
        }
        return auth.getName();
    }
}
