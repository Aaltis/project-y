package fi.breakwaterworks;

import org.springframework.amqp.core.Binding;
import org.springframework.amqp.core.Queue;
import org.springframework.amqp.core.TopicExchange;
import org.springframework.amqp.core.BindingBuilder;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class RabbitConfig {

    public static final String QUEUE_NAME = "logQueue"; // Make sure this matches with your Python producer
    public static final String EXCHANGE_NAME = "logExchange"; // Update if necessary
    public static final String ROUTING_KEY = "logRoutingKey"; // Update if necessary

    @Bean
    public Queue logQueue() {
        return new Queue(QUEUE_NAME, true);
    }

    @Bean
    public TopicExchange logExchange() {
        return new TopicExchange(EXCHANGE_NAME, true, false);  // durable = true, autoDelete = false
    }

    @Bean
    public Binding logBinding() {
        return BindingBuilder.bind(logQueue()).to(logExchange()).with(ROUTING_KEY);
    }
}
