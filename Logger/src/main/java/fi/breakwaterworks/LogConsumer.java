package fi.breakwaterworks;

import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;
import com.fasterxml.jackson.databind.ObjectMapper;

@Component
public class LogConsumer {

    @Autowired
    private LogRepository logRepository;  // JPA repository

    @RabbitListener(queues = RabbitConfig.QUEUE_NAME)
    public void receiveLogMessage(String messageJson) {
    	
    	   try {
    	        // Print the raw message to verify it
    	        System.out.println("messageJson: " + messageJson);

    	        // Deserialize the JSON string to LogMessage object using Jackson
    	        ObjectMapper objectMapper = new ObjectMapper();
    	        LogMessage logMessage = objectMapper.readValue(messageJson, LogMessage.class);

    	        System.out.println("Parsed LogMessage: " + logMessage);
    	        logRepository.save(logMessage);  // Save to PostgreSQL

    	    } catch (Exception e) {
    	        e.printStackTrace();  // Handle exceptions
    	    }

	    }
}

