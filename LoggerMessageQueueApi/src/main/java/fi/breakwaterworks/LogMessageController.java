package fi.breakwaterworks;

import com.fasterxml.jackson.databind.ObjectMapper;

import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@RestController
@RequestMapping("/api/logs")
public class LogMessageController {
	
    private final RabbitTemplate rabbitTemplate;
    private final ObjectMapper objectMapper;
    
    public LogMessageController(RabbitTemplate rabbitTemplate, ObjectMapper objectMapper) {
        this.rabbitTemplate = rabbitTemplate;
        this.objectMapper = objectMapper;
    }

    @PostMapping("/send")
    public ResponseEntity<String> sendMessageToRabbitMQ(@RequestBody LogMessage logMessage) {
        try {
            // Convert the log message to a string (JSON)
            // Serialize the LogMessage object to a JSON string
            String messageJson = objectMapper.writeValueAsString(logMessage);

            // Send the message to RabbitMQ
            rabbitTemplate.convertAndSend("logQueue", messageJson);

            return ResponseEntity.ok("Message sent to RabbitMQ");
        } catch (Exception e) {
            // Return error response if something goes wrong
            return new ResponseEntity<>("Error sending message: " + e.getMessage(), HttpStatus.INTERNAL_SERVER_ERROR);
        }
    }
}
