package fi.breakwaterworks.logconsumer.repository;

import fi.breakwaterworks.logconsumer.model.RequestLog;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

@Repository
public interface RequestLogRepository extends JpaRepository<RequestLog, Long> {
}
