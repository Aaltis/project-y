package fi.breakwaterworks;

import org.springframework.data.jpa.repository.JpaRepository;

public interface LogRepository extends JpaRepository<LogMessage, Long> {
}