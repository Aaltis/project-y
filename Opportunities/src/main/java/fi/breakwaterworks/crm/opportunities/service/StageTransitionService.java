package fi.breakwaterworks.crm.opportunities.service;

import fi.breakwaterworks.crm.opportunities.model.OpportunityStage;
import org.springframework.stereotype.Service;

@Service
public class StageTransitionService {

    public boolean isAllowed(OpportunityStage current, OpportunityStage next) {
        return current.allowedTransitions().contains(next);
    }
}
