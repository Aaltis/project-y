package fi.breakwaterworks.crm.projects.model;

public enum ChangeRequestType {
    SCOPE, SCHEDULE, COST, QUALITY, RISK;

    /** Returns true when approval of a CR with this type must trigger a new baseline draft. */
    public boolean requiresNewBaseline() {
        return this == SCOPE || this == SCHEDULE || this == COST;
    }
}
