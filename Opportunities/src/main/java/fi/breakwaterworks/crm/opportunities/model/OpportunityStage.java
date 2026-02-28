package fi.breakwaterworks.crm.opportunities.model;

import java.util.Set;

public enum OpportunityStage {
    PROSPECT, QUALIFY, PROPOSE, NEGOTIATE, WON, LOST;

    /** Valid next stages. Any stage can transition to LOST; otherwise forward-only. */
    public Set<OpportunityStage> allowedTransitions() {
        return switch (this) {
            case PROSPECT  -> Set.of(QUALIFY,   LOST);
            case QUALIFY   -> Set.of(PROPOSE,   LOST);
            case PROPOSE   -> Set.of(NEGOTIATE, LOST);
            case NEGOTIATE -> Set.of(WON,       LOST);
            case WON, LOST -> Set.of();
        };
    }
}
