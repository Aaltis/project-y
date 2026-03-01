package fi.breakwaterworks.crm.projects.repository;

import fi.breakwaterworks.crm.projects.model.BaselineSet;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface BaselineSetRepository extends JpaRepository<BaselineSet, UUID> {
    List<BaselineSet> findByProjectId(UUID projectId);
    Optional<BaselineSet> findByProjectIdAndVersion(UUID projectId, int version);

    @Query("SELECT MAX(b.version) FROM BaselineSet b WHERE b.projectId = :projectId")
    Optional<Integer> findMaxVersionByProjectId(@Param("projectId") UUID projectId);
}
