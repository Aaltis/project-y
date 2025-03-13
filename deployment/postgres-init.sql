-- Create database
CREATE DATABASE maindb;

-- Create user
CREATE USER mainuser WITH ENCRYPTED PASSWORD 'mysecretpassword';

-- Grant privileges
GRANT ALL PRIVILEGES ON DATABASE maindb TO mainuser;
