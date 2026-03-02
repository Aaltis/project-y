package fi.breakwaterworks.crm.projects.controller;

import fi.breakwaterworks.crm.projects.model.LessonsLearned;
import fi.breakwaterworks.crm.projects.service.ProjectClosingService;
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
@RequestMapping("/api/projects/{projectId}/lessons-learned")
@RequiredArgsConstructor
public class LessonsLearnedController {

    private final ProjectClosingService closingService;

    @PostMapping
    @PreAuthorize("@projectPerm.isMember(#projectId, authentication)")
    public ResponseEntity<LessonsLearned> create(@PathVariable UUID projectId,
                                                  @Valid @RequestBody CreateLessonRequest body,
                                                  Authentication auth) {
        return ResponseEntity.ok(closingService.addLesson(
                projectId, body.getCategory(), body.getWhatHappened(),
                body.getRecommendation(), sub(auth)));
    }

    @GetMapping
    @PreAuthorize("@projectPerm.isMember(#projectId, authentication)")
    public ResponseEntity<List<LessonsLearned>> list(@PathVariable UUID projectId) {
        return ResponseEntity.ok(closingService.listLessons(projectId));
    }

    private String sub(Authentication auth) {
        if (auth.getPrincipal() instanceof Jwt jwt) return jwt.getSubject();
        return auth.getName();
    }

    @Data
    static class CreateLessonRequest {
        private String category;
        @NotBlank
        private String whatHappened;
        private String recommendation;
    }
}
