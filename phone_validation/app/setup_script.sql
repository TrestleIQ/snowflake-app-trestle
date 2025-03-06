-- This is the setup script that runs while installing a Snowflake Native App in a consumer account.
-- To write this script, you can familiarize yourself with some of the following concepts:
-- Application Roles
-- Versioned Schemas
-- UDFs/Procs
-- Extension Code
-- Refer to https://docs.snowflake.com/en/developer-guide/native-apps/creating-setup-script for a detailed understanding of this file.

-- CREATE OR ALTER VERSIONED SCHEMA core;

-- The rest of this script is left blank for purposes of your learning and exploration.
CREATE APPLICATION ROLE IF NOT EXISTS app_public;
CREATE SCHEMA IF NOT EXISTS core;
GRANT USAGE ON SCHEMA core TO APPLICATION ROLE app_public;

CREATE OR ALTER VERSIONED SCHEMA code_schema;
GRANT USAGE ON SCHEMA code_schema TO APPLICATION ROLE app_public;


CREATE or replace PROCEDURE code_schema.register_callback(ref_name STRING, operation STRING, ref_or_alias STRING)
  RETURNS STRING
  LANGUAGE SQL
  AS $$
    BEGIN
      CASE (operation)
        WHEN 'ADD' THEN
          SELECT SYSTEM$ADD_REFERENCE(:ref_name, :ref_or_alias);
        WHEN 'REMOVE' THEN
          SELECT SYSTEM$REMOVE_REFERENCE(:ref_name, :ref_or_alias);
        WHEN 'CLEAR' THEN
          SELECT SYSTEM$REMOVE_ALL_REFERENCES(:ref_name);
      ELSE
        RETURN 'unknown operation: ' || operation;
      END CASE;
      RETURN NULL;
    END;
  $$;

GRANT USAGE ON PROCEDURE code_schema.register_callback(STRING, STRING, STRING)
  TO APPLICATION ROLE app_public;

CREATE OR REPLACE PROCEDURE code_schema.get_config_for_ref(ref_name STRING)
    RETURNS STRING
    LANGUAGE SQL
    AS
    $$
    BEGIN
      CASE (ref_name)
        WHEN 'CONSUMER_EXTERNAL_ACCESS' THEN
          RETURN '{
            "type": "CONFIGURATION",
            "payload":{
              "host_ports":["api.trestleiq.com"],
              "allowed_secrets" : "LIST",
              "secret_references":["CONSUMER_SECRET"]}}';
        WHEN 'CONSUMER_SECRET' THEN
          RETURN '{
            "type": "CONFIGURATION",
            "payload":{
              "type" : "GENERIC_STRING",
              "security_integration": {}
							 }}';
  END CASE;
  RETURN '';
  END;
  $$;

GRANT USAGE ON PROCEDURE code_schema.get_config_for_ref(string) TO APPLICATION ROLE app_public;


CREATE OR REPLACE PROCEDURE code_schema.create_eai_objects()
RETURNS STRING
LANGUAGE SQL
AS 
$$
BEGIN
create or replace function code_schema.validate_phone(ph_nos ARRAY)
returns table(phno varchar, data variant)
language python
PACKAGES=('snowflake-snowpark-python', 'requests') 
external_access_integrations =  (reference('consumer_external_access'))
SECRETS = ('cred' = reference('consumer_secret'))
RUNTIME_VERSION = '3.9'
imports = ('/src/udf1.py')
handler = 'udf1.validate_phone';

GRANT USAGE ON FUNCTION code_schema.validate_phone(ARRAY) TO APPLICATION ROLE app_public;

RETURN 'SUCCESS';
END;	
$$;

GRANT USAGE ON PROCEDURE code_schema.create_eai_objects() TO APPLICATION ROLE app_public;