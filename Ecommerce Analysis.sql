
-- CTE 1: Account registration metrics

WITH registration_base AS (
  SELECT
    sp.country,
    s.date AS date,
    acc.send_interval,
    acc.is_verified,
    acc.is_unsubscribed,
    COUNT(DISTINCT accs.account_id) AS account_cnt
  FROM `DA.session`         s
  JOIN `DA.session_params`  sp   USING (ga_session_id)
  JOIN `DA.account_session` accs USING (ga_session_id)
  JOIN `DA.account`         acc  ON accs.account_id = acc.id
  GROUP BY 1, 2, 3, 4, 5
),


-- CTE 2: Email engagement metrics
--        date = session date + offset stored in email_sent.sent_date (in days)
--        LEFT JOINs for opens / visits preserve unengaged messages as 0.

email_metrics AS (
  SELECT
    sp.country,
    DATE_ADD(s.date, INTERVAL sent.sent_date DAY) AS date,
    acc.send_interval,
    acc.is_verified,
    acc.is_unsubscribed,
    COUNT(sent.id_message)  AS sent_msg,
    COUNT(open.id_message)  AS open_msg,
    COUNT(visit.id_message) AS visit_msg
  FROM `DA.email_sent`      sent
  LEFT JOIN `DA.email_open`  open  USING (id_message)
  LEFT JOIN `DA.email_visit` visit USING (id_message)
  JOIN `DA.account`          acc   ON sent.id_account = acc.id
  JOIN `DA.account_session`  accs  ON sent.id_account = accs.account_id
  JOIN `DA.session`          s     USING (ga_session_id)
  JOIN `DA.session_params`   sp    USING (ga_session_id)
  GROUP BY 1, 2, 3, 4, 5
),


-- CTE 3: UNION — merge account and email rows into one dataset
--        Account rows carry 0 for email metrics; email rows carry 0 for account_cnt

combined_data AS (
  SELECT
    country,
    date, send_interval, 
    is_verified, is_unsubscribed,
    account_cnt,
    0 AS sent_msg,
    0 AS open_msg,
    0 AS visit_msg
  FROM registration_base

  UNION ALL

  SELECT
    country, 
    date, send_interval, 
    is_verified, is_unsubscribed,
    0 AS account_cnt,
    sent_msg, open_msg, visit_msg
  FROM email_metrics
),


-- CTE 4: Collapse duplicate rows that arise from the UNION
 
grouped_dataset AS (
  SELECT
    country, date, send_interval, is_verified, is_unsubscribed,
    SUM(account_cnt) AS account_cnt,
    SUM(sent_msg)    AS sent_msg,
    SUM(open_msg)    AS open_msg,
    SUM(visit_msg)   AS visit_msg
  FROM combined_data
  GROUP BY 1, 2, 3, 4, 5
),


-- CTE 5: Country-level totals via window functions 
 
total_metrics AS (
  SELECT
    *,
    SUM(account_cnt) OVER (PARTITION BY country) AS total_country_account_cnt,
    SUM(sent_msg)    OVER (PARTITION BY country) AS total_country_sent_cnt
  FROM grouped_dataset
),

 
-- CTE 6: Country rankings — DENSE_RANK so ties share the same position
 
ranked_data AS (
  SELECT
    *,
    DENSE_RANK() OVER (ORDER BY total_country_account_cnt DESC) AS rank_total_country_account_cnt,
    DENSE_RANK() OVER (ORDER BY total_country_sent_cnt    DESC) AS rank_total_country_sent_cnt
  FROM total_metrics
)

 
-- Final SELECT: keep only top-10 countries by either ranking
 
SELECT
  date,
  country,
  send_interval,
  is_verified,
  is_unsubscribed,
  account_cnt,
  sent_msg,
  open_msg,
  visit_msg,
  total_country_account_cnt,
  total_country_sent_cnt,
  rank_total_country_account_cnt,
  rank_total_country_sent_cnt
FROM ranked_data
WHERE rank_total_country_account_cnt <= 10
   OR rank_total_country_sent_cnt    <= 10
ORDER BY rank_total_country_account_cnt, date;
