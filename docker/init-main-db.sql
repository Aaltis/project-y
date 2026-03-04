-- Runs once on first postgres container start (empty data directory).
-- Creates all application databases; postgres superuser owns them all.

CREATE DATABASE maindb;
CREATE DATABASE accountsdb;
CREATE DATABASE contactsdb;
CREATE DATABASE opportunitiesdb;
CREATE DATABASE activitiesdb;
CREATE DATABASE projectsdb;
CREATE DATABASE diagramsdb;
