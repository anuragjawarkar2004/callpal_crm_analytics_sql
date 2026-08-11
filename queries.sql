-- ============================================================
-- CallPal CRM Analytics — Query Set
-- Progression: basic aggregation -> joins -> window functions -> CTEs
-- ============================================================


-- ------------------------------------------------------------
-- SECTION 1: BASIC AGGREGATION
-- ------------------------------------------------------------

-- 1.1 Total calls made, grouped by outcome
SELECT outcome, COUNT(*) AS total_calls
FROM calls
GROUP BY outcome
ORDER BY total_calls DESC;

-- 1.2 Total leads captured by source
SELECT source, COUNT(*) AS total_leads
FROM leads
GROUP BY source
ORDER BY total_leads DESC;

-- 1.3 Average call duration for connected calls (in seconds)
SELECT ROUND(AVG(duration_seconds), 1) AS avg_connected_duration_sec
FROM calls
WHERE outcome = 'Connected';

-- 1.4 Number of leads by current status
SELECT status, COUNT(*) AS lead_count
FROM leads
GROUP BY status
ORDER BY lead_count DESC;


-- ------------------------------------------------------------
-- SECTION 2: JOINS
-- ------------------------------------------------------------

-- 2.1 Lead-to-conversion rate by source
-- (business question: which channel gives the best ROI on lead gen?)
SELECT
    l.source,
    COUNT(*) AS total_leads,
    SUM(CASE WHEN l.status = 'Converted' THEN 1 ELSE 0 END) AS converted_leads,
    ROUND(100.0 * SUM(CASE WHEN l.status = 'Converted' THEN 1 ELSE 0 END) / COUNT(*), 2) AS conversion_rate_pct
FROM leads l
GROUP BY l.source
ORDER BY conversion_rate_pct DESC;

-- 2.2 Calls handled per agent, with agent name and team
SELECT
    a.agent_name,
    a.team,
    COUNT(c.call_id) AS total_calls,
    SUM(CASE WHEN c.outcome = 'Connected' THEN 1 ELSE 0 END) AS connected_calls
FROM agents a
LEFT JOIN calls c ON a.agent_id = c.agent_id
GROUP BY a.agent_id, a.agent_name, a.team
ORDER BY total_calls DESC;

-- 2.3 Total pipeline value (open opportunities) per agent
SELECT
    a.agent_name,
    a.team,
    COUNT(o.opp_id) AS open_opportunities,
    SUM(o.deal_value) AS pipeline_value
FROM agents a
JOIN leads l ON a.agent_id = l.agent_id
JOIN opportunities o ON l.lead_id = o.lead_id
WHERE o.stage IN ('Prospecting', 'Proposal', 'Negotiation')
GROUP BY a.agent_id, a.agent_name, a.team
ORDER BY pipeline_value DESC;

-- 2.4 Closed-won revenue by team
SELECT
    a.team,
    COUNT(o.opp_id) AS deals_won,
    SUM(o.deal_value) AS total_revenue
FROM agents a
JOIN leads l ON a.agent_id = l.agent_id
JOIN opportunities o ON l.lead_id = o.lead_id
WHERE o.stage = 'Closed Won'
GROUP BY a.team
ORDER BY total_revenue DESC;


-- ------------------------------------------------------------
-- SECTION 3: WINDOW FUNCTIONS
-- ------------------------------------------------------------

-- 3.1 Rank agents by number of calls handled, within their team
SELECT
    a.team,
    a.agent_name,
    COUNT(c.call_id) AS total_calls,
    RANK() OVER (PARTITION BY a.team ORDER BY COUNT(c.call_id) DESC) AS rank_in_team
FROM agents a
LEFT JOIN calls c ON a.agent_id = c.agent_id
GROUP BY a.team, a.agent_id, a.agent_name
ORDER BY a.team, rank_in_team;

-- 3.2 Agent connect rate vs team average (highlights over/under performers)
SELECT
    agent_name,
    team,
    connect_rate_pct,
    ROUND(AVG(connect_rate_pct) OVER (PARTITION BY team), 2) AS team_avg_connect_rate,
    ROUND(connect_rate_pct - AVG(connect_rate_pct) OVER (PARTITION BY team), 2) AS diff_from_team_avg
FROM (
    SELECT
        a.agent_id,
        a.agent_name,
        a.team,
        ROUND(100.0 * SUM(CASE WHEN c.outcome = 'Connected' THEN 1 ELSE 0 END) / COUNT(c.call_id), 2) AS connect_rate_pct
    FROM agents a
    JOIN calls c ON a.agent_id = c.agent_id
    GROUP BY a.agent_id, a.agent_name, a.team
) agent_stats
ORDER BY team, diff_from_team_avg DESC;

-- 3.3 Month-over-month new lead growth
SELECT
    DATE_FORMAT(created_date, '%Y-%m') AS month,
    COUNT(*) AS new_leads,
    LAG(COUNT(*)) OVER (ORDER BY DATE_FORMAT(created_date, '%Y-%m')) AS prev_month_leads,
    ROUND(
        100.0 * (COUNT(*) - LAG(COUNT(*)) OVER (ORDER BY DATE_FORMAT(created_date, '%Y-%m')))
        / LAG(COUNT(*)) OVER (ORDER BY DATE_FORMAT(created_date, '%Y-%m')), 2
    ) AS mom_growth_pct
FROM leads
GROUP BY month
ORDER BY month;

-- 3.4 Running total of closed-won revenue over time
SELECT
    closed_date,
    deal_value,
    SUM(deal_value) OVER (ORDER BY closed_date) AS running_total_revenue
FROM opportunities
WHERE stage = 'Closed Won'
ORDER BY closed_date;


-- ------------------------------------------------------------
-- SECTION 4: CTEs — SALES FUNNEL / PIPELINE ANALYSIS
-- ------------------------------------------------------------

-- 4.1 Lead funnel with stage-wise drop-off percentage
WITH funnel AS (
    SELECT
        SUM(CASE WHEN status IN ('New','Contacted','Qualified','Converted') THEN 1 ELSE 0 END) AS total_leads,
        SUM(CASE WHEN status IN ('Contacted','Qualified','Converted') THEN 1 ELSE 0 END) AS contacted,
        SUM(CASE WHEN status IN ('Qualified','Converted') THEN 1 ELSE 0 END) AS qualified,
        SUM(CASE WHEN status = 'Converted' THEN 1 ELSE 0 END) AS converted
    FROM leads
)
SELECT
    total_leads,
    contacted,
    ROUND(100.0 * contacted / total_leads, 2) AS contacted_pct,
    qualified,
    ROUND(100.0 * qualified / total_leads, 2) AS qualified_pct,
    converted,
    ROUND(100.0 * converted / total_leads, 2) AS converted_pct
FROM funnel;

-- 4.2 Signature query — TEAM PERFORMANCE DASHBOARD
-- (mirrors the actual Power BI dashboard: volume, quality, and conversion in one view)
WITH call_stats AS (
    SELECT
        agent_id,
        COUNT(*) AS total_calls,
        SUM(CASE WHEN outcome = 'Connected' THEN 1 ELSE 0 END) AS connected_calls,
        ROUND(AVG(CASE WHEN outcome = 'Connected' THEN duration_seconds END), 1) AS avg_call_duration
    FROM calls
    GROUP BY agent_id
),
deal_stats AS (
    SELECT
        l.agent_id,
        COUNT(CASE WHEN o.stage = 'Closed Won' THEN 1 END) AS deals_won,
        COALESCE(SUM(CASE WHEN o.stage = 'Closed Won' THEN o.deal_value END), 0) AS revenue_won
    FROM leads l
    LEFT JOIN opportunities o ON l.lead_id = o.lead_id
    GROUP BY l.agent_id
)
SELECT
    a.agent_name,
    a.team,
    cs.total_calls,
    cs.connected_calls,
    ROUND(100.0 * cs.connected_calls / cs.total_calls, 2) AS connect_rate_pct,
    cs.avg_call_duration,
    ds.deals_won,
    ds.revenue_won,
    RANK() OVER (ORDER BY ds.revenue_won DESC) AS revenue_rank
FROM agents a
JOIN call_stats cs ON a.agent_id = cs.agent_id
JOIN deal_stats ds ON a.agent_id = ds.agent_id
ORDER BY revenue_rank;

-- 4.3 Leads that went cold — no call in the last 14 days of the dataset, still open
WITH last_call AS (
    SELECT lead_id, MAX(call_date) AS last_call_date
    FROM calls
    GROUP BY lead_id
)
SELECT
    l.lead_id,
    l.lead_name,
    l.source,
    l.status,
    lc.last_call_date
FROM leads l
JOIN last_call lc ON l.lead_id = lc.lead_id
WHERE l.status IN ('New', 'Contacted', 'Qualified')
  AND lc.last_call_date <= DATE_SUB((SELECT MAX(call_date) FROM calls), INTERVAL 14 DAY)
ORDER BY lc.last_call_date;
