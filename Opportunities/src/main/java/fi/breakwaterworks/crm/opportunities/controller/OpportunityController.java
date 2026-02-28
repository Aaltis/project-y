package fi.breakwaterworks.crm.opportunities.controller;

import fi.breakwaterworks.crm.opportunities.model.Opportunity;
import fi.breakwaterworks.crm.opportunities.model.OpportunityStage;
import fi.breakwaterworks.crm.opportunities.repository.OpportunityRepository;
import fi.breakwaterworks.crm.opportunities.service.StageTransitionService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.domain.Specification;
import org.springframework.data.web.PageableDefault;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDate;
import java.util.Map;
import java.util.UUID;

@RestController
@RequestMapping("/api/opportunities")
@RequiredArgsConstructor
public class OpportunityController {

    private final OpportunityRepository opportunityRepository;
    private final StageTransitionService stageTransitionService;

    @GetMapping
    public Page<Opportunity> list(
            @RequestParam(required = false) UUID accountId,
            @RequestParam(required = false) OpportunityStage stage,
            @RequestParam(required = false) LocalDate closingBefore,
            @RequestParam(defaultValue = "false") boolean mine,
            @PageableDefault(size = 20) Pageable pageable,
            Authentication auth) {

        boolean isAdmin = auth.getAuthorities().stream()
                .anyMatch(a -> a.getAuthority().equals("ROLE_crm_admin"));

        Specification<Opportunity> spec = Specification.where(null);

        if (accountId != null) {
            spec = spec.and((r, q, cb) -> cb.equal(r.get("accountId"), accountId));
        }
        if (stage != null) {
            spec = spec.and((r, q, cb) -> cb.equal(r.get("stage"), stage));
        }
        if (closingBefore != null) {
            spec = spec.and((r, q, cb) -> cb.lessThan(r.get("closeDate"), closingBefore));
        }
        if (mine || !isAdmin) {
            spec = spec.and((r, q, cb) -> cb.equal(r.get("ownerId"), sub(auth)));
        }

        return opportunityRepository.findAll(spec, pageable);
    }

    @PostMapping
    public ResponseEntity<Opportunity> create(@Valid @RequestBody Opportunity opportunity, Authentication auth) {
        opportunity.setOwnerId(sub(auth));
        return ResponseEntity.ok(opportunityRepository.save(opportunity));
    }

    @GetMapping("/{id}")
    @PreAuthorize("@perm.canAccess(#id, authentication)")
    public ResponseEntity<Opportunity> get(@PathVariable UUID id) {
        return opportunityRepository.findById(id)
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }

    @PutMapping("/{id}")
    @PreAuthorize("@perm.canAccess(#id, authentication)")
    public ResponseEntity<Opportunity> update(@PathVariable UUID id, @Valid @RequestBody Opportunity body) {
        return opportunityRepository.findById(id).map(existing -> {
            existing.setName(body.getName());
            existing.setAmount(body.getAmount());
            existing.setCloseDate(body.getCloseDate());
            return ResponseEntity.ok(opportunityRepository.save(existing));
        }).orElse(ResponseEntity.notFound().build());
    }

    @PatchMapping("/{id}/stage")
    @PreAuthorize("@perm.canAccess(#id, authentication)")
    public ResponseEntity<?> updateStage(@PathVariable UUID id, @RequestBody Map<String, String> body) {
        OpportunityStage newStage;
        try {
            newStage = OpportunityStage.valueOf(body.get("stage"));
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body("Invalid stage value");
        }
        return opportunityRepository.findById(id).map(existing -> {
            if (!stageTransitionService.isAllowed(existing.getStage(), newStage)) {
                return ResponseEntity.badRequest()
                        .body("Transition from " + existing.getStage() + " to " + newStage + " is not allowed");
            }
            existing.setStage(newStage);
            return ResponseEntity.ok(opportunityRepository.save(existing));
        }).orElse(ResponseEntity.notFound().build());
    }

    @DeleteMapping("/{id}")
    @PreAuthorize("@perm.canAccess(#id, authentication)")
    public ResponseEntity<Void> delete(@PathVariable UUID id) {
        if (!opportunityRepository.existsById(id)) return ResponseEntity.notFound().build();
        opportunityRepository.deleteById(id);
        return ResponseEntity.noContent().build();
    }

    private String sub(Authentication auth) {
        if (auth.getPrincipal() instanceof Jwt jwt) {
            return jwt.getSubject();
        }
        return auth.getName();
    }
}
