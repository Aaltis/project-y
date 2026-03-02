package fi.breakwaterworks.crm.projects.model;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import org.hibernate.annotations.CreationTimestamp;

import java.time.LocalDateTime;
import java.util.UUID;

@Entity
@Table(name = "lessons_learned")
@Getter @Setter @NoArgsConstructor
public class LessonsLearned {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @Column(name = "project_id", nullable = false)
    private UUID projectId;

    @Column
    private String category;

    @Column(name = "what_happened", nullable = false, columnDefinition = "TEXT")
    private String whatHappened;

    @Column(columnDefinition = "TEXT")
    private String recommendation;

    @Column(name = "created_by", nullable = false)
    private String createdBy;

    @CreationTimestamp
    @Column(name = "created_at", updatable = false)
    private LocalDateTime createdAt;
}
