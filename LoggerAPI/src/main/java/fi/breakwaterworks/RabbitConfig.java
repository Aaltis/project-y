package fi.breakwaterworks;

import org.springframework.amqp.core.Queue;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class RabbitConfig {

    // Declare the queue name
    @Bean
    public Queue logQueue() {
        return new Queue("logQueue", true); // Durable queue
    }
}