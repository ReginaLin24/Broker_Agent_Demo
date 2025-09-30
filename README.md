# Snowflake Intelligence Demo for Brokers

This repository provides a turnkey demo that gives brokers a single interface to query both structured and unstructured data in Snowflake. It showcases Snowflake Intelligence with Cortex Analyst and Cortex Search, plus Git integration for automated data loading.

## Repository Structure

- `demo_data/`
  - `clients.csv` – `client_id`, `name`, `risk_tolerance`, `portfolio_value`
  - `transactions.csv` – `transaction_id`, `client_id`, `transaction_date`, `amount`, `stock_ticker`
  - `broker_performance.csv` – `broker_id`, `number_of_clients`, `total_assets_under_management`
- `unstructured_docs/` – 25 call transcripts as rich text files, each embedding `client_id` and `broker_id` metadata
- `sql_scripts/`
  - `setup.sql` – single script to set up all demo objects in Snowflake

## Prerequisites

- A Snowflake account with access to use `ACCOUNTADMIN`
- A GitHub repository hosting this project (or update the URLs in `setup.sql`)

## Setup (Single Command)

Run inside Snowflake (Snowsight or CLI):

```sql
-- Option A: Execute from the Snowflake Git repo reference after you create it
-- EXECUTE IMMEDIATE FROM @BROKER_DEMO_REPO/branches/main/sql_scripts/setup.sql;

-- Option B: Paste-and-run the file contents in a worksheet
```

Update in `setup.sql` before running:
- Replace `https://github.com/your_org/your_repo` with the actual repository URL.

## What `setup.sql` Does

1. Uses `ACCOUNTADMIN` and creates a small warehouse with auto-suspend
2. Creates `BROKER_DEMO_DB.DEMO` schema
3. Creates a Snowflake Git integration and repository pointing to your GitHub repo
4. Creates tables and loads demo CSVs via `COPY INTO` from the Git stage
5. Creates a `CLIENT_PORTFOLIO_VIEW` for natural language queries
6. Includes commented DDL templates for:
   - A Cortex Search service over transcripts
   - A Cortex Analyst over the semantic view
   - A Snowflake Intelligence Agent orchestrating both

## Demo Script: Example Questions for the Intelligence Agent

- Analyze structured data: “Show me my top clients by total portfolio value and number of transactions.”
- Search unstructured data: “Find all calls where a client mentioned ‘buying Apple stock’ or ‘long-term investment strategy’.”
- Multi-tool orchestration: “Summarize my last three calls with client ‘Jane Doe’ and show me her recent transaction history for tech stocks.”
- Visualization: “Show me the monthly trend of total transaction amounts for all my clients in a bar chart.”

## Notes

- Cortex DDL may vary across account releases. If a `CREATE ... CORTEX ...` statement fails, please consult Snowflake docs for your edition and update the script accordingly.
- For private repositories, add a `SECRET` and adjust the API integration to authenticate.
