-- Snowflake Demo Setup Script for Broker Intelligence
-- Assumptions:
-- - A Snowflake Git repository object will be created pointing to your GitHub repo
-- - Branch 'main' contains `demo_data/` and `unstructured_docs/`
-- - Execute with a role that can create roles, warehouses, DBs, schemas, API integrations, and git repositories

-- 1) Role and Warehouse
USE ROLE ACCOUNTADMIN;

CREATE OR REPLACE WAREHOUSE BROKER_DEMO_WH
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE;

-- 2) Database and Schema
CREATE OR REPLACE DATABASE BROKER_DEMO_DB;
CREATE OR REPLACE SCHEMA BROKER_DEMO_DB.DEMO;

USE WAREHOUSE BROKER_DEMO_WH;
USE DATABASE BROKER_DEMO_DB;
USE SCHEMA DEMO;

-- 3) Git Integration (update ORIGIN to your GitHub URL)
-- Optionally create a secret for Git credentials if needed
-- CREATE OR REPLACE SECRET GIT_CRED TYPE = 'PASSWORD' USERNAME = '<GIT_USER>' PASSWORD = '<GIT_TOKEN>'; -- if using private repo

CREATE OR REPLACE API INTEGRATION BROKER_DEMO_GIT_API
  API_PROVIDER = git_https_api
  API_ALLOWED_PREFIXES = ('https://github.com/your_org/your_repo')
  ENABLED = TRUE;

CREATE OR REPLACE GIT REPOSITORY BROKER_DEMO_REPO
  API_INTEGRATION = BROKER_DEMO_GIT_API
  ORIGIN = 'https://github.com/your_org/your_repo';

ALTER GIT REPOSITORY BROKER_DEMO_REPO FETCH;

-- File format and internal stage for copying repo files
CREATE OR REPLACE FILE FORMAT CSV_FORMAT
  TYPE = 'CSV'
  FIELD_DELIMITER = ','
  RECORD_DELIMITER = '\n'
  SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  TRIM_SPACE = TRUE
  ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE
  ESCAPE = 'NONE'
  ESCAPE_UNENCLOSED_FIELD = '\\134'
  DATE_FORMAT = 'YYYY-MM-DD'
  TIMESTAMP_FORMAT = 'YYYY-MM-DD HH24:MI:SS'
  NULL_IF = ('NULL','null','','N/A','n/a');

CREATE OR REPLACE STAGE INTERNAL_DATA_STAGE
  FILE_FORMAT = CSV_FORMAT
  COMMENT = 'Internal stage for copied demo data files'
  DIRECTORY = (ENABLE = TRUE)
  ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE');

-- Copy repo files into internal stage for consistent loading
COPY FILES
INTO @INTERNAL_DATA_STAGE/demo_data/
FROM @BROKER_DEMO_REPO/branches/main/demo_data/;

COPY FILES
INTO @INTERNAL_DATA_STAGE/unstructured_docs/
FROM @BROKER_DEMO_REPO/branches/main/unstructured_docs/;

-- Optional verification
LS @INTERNAL_DATA_STAGE | CAT;
ALTER STAGE INTERNAL_DATA_STAGE REFRESH;

-- 4) Create Tables
CREATE OR REPLACE TABLE CLIENTS (
  CLIENT_ID INT,
  NAME STRING,
  RISK_TOLERANCE STRING,
  PORTFOLIO_VALUE FLOAT
);

CREATE OR REPLACE TABLE TRANSACTIONS (
  TRANSACTION_ID INT,
  CLIENT_ID INT,
  TRANSACTION_DATE DATE,
  AMOUNT FLOAT,
  STOCK_TICKER STRING
);

CREATE OR REPLACE TABLE BROKER_PERFORMANCE (
  BROKER_ID INT,
  NUMBER_OF_CLIENTS INT,
  TOTAL_ASSETS_UNDER_MANAGEMENT FLOAT
);

-- Optional table to land transcripts as rows (if desired by Cortex Search variant)
CREATE OR REPLACE TABLE CALL_TRANSCRIPTS (
  FILE_NAME STRING,
  CONTENT STRING
);

-- 5) Load data from Git repository stage
-- Note: @BROKER_DEMO_REPO/branches/main/ is the stage-like reference to your repo
COPY INTO CLIENTS
  FROM @INTERNAL_DATA_STAGE/demo_data/clients.csv
  FILE_FORMAT = (TYPE = CSV FIELD_OPTIONALLY_ENCLOSED_BY = '"' SKIP_HEADER = 1);

COPY INTO TRANSACTIONS
  FROM @INTERNAL_DATA_STAGE/demo_data/transactions.csv
  FILE_FORMAT = (TYPE = CSV FIELD_OPTIONALLY_ENCLOSED_BY = '"' SKIP_HEADER = 1);

COPY INTO BROKER_PERFORMANCE
  FROM @INTERNAL_DATA_STAGE/demo_data/broker_performance.csv
  FILE_FORMAT = (TYPE = CSV FIELD_OPTIONALLY_ENCLOSED_BY = '"' SKIP_HEADER = 1);

-- Unstructured docs are available on stage; will be used directly by Cortex Search

-- 6) Semantic view for structured NL queries
CREATE OR REPLACE VIEW CLIENT_PORTFOLIO_VIEW COMMENT = 'Combines client profiles with transaction history for broker NL queries' AS
SELECT
  c.CLIENT_ID,
  c.NAME,
  c.RISK_TOLERANCE,
  c.PORTFOLIO_VALUE,
  t.TRANSACTION_ID,
  t.TRANSACTION_DATE,
  t.AMOUNT,
  t.STOCK_TICKER
FROM CLIENTS c
JOIN TRANSACTIONS t ON c.CLIENT_ID = t.CLIENT_ID;

-- 7) Semantic View for structured NL queries (relationships, facts, dimensions, metrics)
-- Requires accounts with SEMANTIC VIEW support
CREATE OR REPLACE SEMANTIC VIEW BROKER_SEMANTIC_VIEW
  TABLES (
    CLIENTS AS CLIENTS PRIMARY KEY (CLIENT_ID) WITH SYNONYMS=('clients','investors') COMMENT='Broker clients and risk profiles',
    TRANSACTIONS AS TRANSACTIONS PRIMARY KEY (TRANSACTION_ID) WITH SYNONYMS=('trades','orders') COMMENT='Client transaction history',
    BROKERS AS BROKER_PERFORMANCE PRIMARY KEY (BROKER_ID) WITH SYNONYMS=('advisors','brokers') COMMENT='Broker coverage and AUM'
  )
  RELATIONSHIPS (
    TX_TO_CLIENT AS TRANSACTIONS(CLIENT_ID) REFERENCES CLIENTS(CLIENT_ID)
  )
  FACTS (
    TRANSACTIONS.AMOUNT AS amount COMMENT='Signed transaction amount (+buy, -sell)',
    TRANSACTIONS.TX_COUNT AS 1 COMMENT='Transaction count'
  )
  DIMENSIONS (
    CLIENTS.NAME AS client_name WITH SYNONYMS=('name','client'),
    CLIENTS.RISK_TOLERANCE AS risk_tolerance,
    CLIENTS.PORTFOLIO_VALUE AS portfolio_value,
    TRANSACTIONS.TRANSACTION_DATE AS date WITH SYNONYMS=('date','trade date'),
    TRANSACTIONS.STOCK_TICKER AS stock_ticker,
    BROKERS.NUMBER_OF_CLIENTS AS number_of_clients,
    BROKERS.TOTAL_ASSETS_UNDER_MANAGEMENT AS aum
  )
  METRICS (
    TRANSACTIONS.TOTAL_AMOUNT AS SUM(transactions.amount) COMMENT='Total transacted amount',
    TRANSACTIONS.TOTAL_TRANSACTIONS AS COUNT(transactions.tx_count) COMMENT='Number of transactions',
    TRANSACTIONS.AVG_TRADE_AMOUNT AS AVG(transactions.amount) COMMENT='Average trade size'
  )
  COMMENT='Semantic model joining clients, transactions and broker KPIs for NL analytics';

-- 8) Cortex Search over transcripts on the internal stage (adjust syntax per account release)
-- If supported in your account:
-- Creates a semantic search index over TXT transcripts in @INTERNAL_DATA_STAGE/unstructured_docs/
CREATE OR REPLACE CORTEX SEARCH SERVICE BROKER_CALL_SEARCH
  ON STAGE @INTERNAL_DATA_STAGE/unstructured_docs/
  FILE_FORMAT = (TYPE = 'TEXT')
  WAREHOUSE = BROKER_DEMO_WH;

-- 9) Snowflake Intelligence Agent orchestrating semantic SQL and search
-- Ensure the Snowflake Intelligence config database exists
CREATE DATABASE IF NOT EXISTS snowflake_intelligence;
CREATE SCHEMA IF NOT EXISTS snowflake_intelligence.agents;
GRANT USAGE ON DATABASE snowflake_intelligence TO ROLE PUBLIC;
GRANT USAGE ON SCHEMA snowflake_intelligence.agents TO ROLE PUBLIC;

CREATE OR REPLACE AGENT snowflake_intelligence.agents.BROKER_DEMO_AGENT
WITH PROFILE='{ "display_name": "Broker Intelligence Agent" }'
FROM SPECIFICATION $$
{
  "instructions": {
    "response": "You assist financial brokers. Use semantic SQL for structured questions over clients and transactions. Use search for call transcript questions. Show simple charts when asked.",
    "sample_questions": [
      { "question": "Show my top clients by portfolio value and number of transactions." },
      { "question": "Find calls mentioning buying Apple stock or long-term strategy." },
      { "question": "Summarize last three calls with client Jane Doe and list recent tech trades." },
      { "question": "Show monthly trend of total transaction amounts in a bar chart." }
    ]
  },
  "tools": [
    { "tool_spec": { "type": "cortex_analyst_text_to_sql", "name": "Query Clients & Transactions", "description": "Natural language to SQL over the broker semantic model." } },
    { "tool_spec": { "type": "cortex_search", "name": "Search Call Transcripts", "description": "Semantic search over call transcripts." } }
  ],
  "tool_resources": {
    "Query Clients & Transactions": { "semantic_view": "BROKER_DEMO_DB.DEMO.BROKER_SEMANTIC_VIEW" },
    "Search Call Transcripts": { "name": "BROKER_DEMO_DB.DEMO.BROKER_CALL_SEARCH", "max_results": 10 }
  }
}
$$
COMMENT='Primary interface for unified broker intelligence across structured and unstructured data.';

-- Notes:
-- - The exact DDL for Cortex objects may differ based on Snowflake release. If CREATE ... statements fail, consult Snowflake docs for your account's current syntax and adjust.
