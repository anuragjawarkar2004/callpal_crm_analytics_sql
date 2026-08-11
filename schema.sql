-- ============================================
-- CallPal CRM Analytics — Schema
-- CRM for SMEs: lead tracking, call logging, opportunity pipeline
-- ============================================

DROP TABLE IF EXISTS opportunities;
DROP TABLE IF EXISTS calls;
DROP TABLE IF EXISTS leads;
DROP TABLE IF EXISTS agents;

CREATE TABLE agents (
    agent_id     INT PRIMARY KEY,
    agent_name   VARCHAR(100) NOT NULL,
    team         VARCHAR(50),
    join_date    DATE
);

CREATE TABLE leads (
    lead_id       INT PRIMARY KEY,
    lead_name     VARCHAR(100) NOT NULL,
    source        VARCHAR(50),      -- Website, Referral, Cold Call, Social Media, Email Campaign
    status        VARCHAR(30),      -- New, Contacted, Qualified, Converted, Lost
    created_date  DATE,
    agent_id      INT,
    FOREIGN KEY (agent_id) REFERENCES agents(agent_id)
);

CREATE TABLE calls (
    call_id           INT PRIMARY KEY,
    lead_id           INT,
    agent_id          INT,
    call_date         DATE,
    call_type         VARCHAR(20),   -- Outbound, Inbound
    outcome           VARCHAR(30),   -- Connected, No Answer, Busy, Voicemail, Callback Requested
    duration_seconds  INT,
    FOREIGN KEY (lead_id) REFERENCES leads(lead_id),
    FOREIGN KEY (agent_id) REFERENCES agents(agent_id)
);

CREATE TABLE opportunities (
    opp_id        INT PRIMARY KEY,
    lead_id       INT,
    stage         VARCHAR(30),   -- Prospecting, Proposal, Negotiation, Closed Won, Closed Lost
    deal_value    INT,           -- INR
    created_date  DATE,
    closed_date   DATE,
    FOREIGN KEY (lead_id) REFERENCES leads(lead_id)
);
