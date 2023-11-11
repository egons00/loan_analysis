--Creating views for import in PowerBI for a clean data model
--With the current data no snowflake model is possible. only star schema
--Same assumptions as in SQL queries
--2 RAW dim tables, 2 RAW fact tables + 1 temp table as VIEW + outstanding VIEW + Calculated Dim Table in PBI (Dim Dates)

CREATE OR REPLACE VIEW daily_outstanding AS
WITH day_loan_amount AS (
    SELECT origination_date::date AS date
         , SUM(loan_amount)       AS loan_amount
    FROM loans l
    WHERE 1 = 1
      AND l.status NOT IN (1, 8)
    GROUP BY 1
)
   , day_payments    AS (
    SELECT payment_date::date  AS date
         , SUM(payment_amount) AS payment_amount
    FROM payments p
    WHERE 1 = 1
      AND (p.status != 9999 AND p.payment_amount != 0)
    GROUP BY 1
)
SELECT date
     , loan_amount_end
     , payment_amount_end
     , (payment_amount_end - loan_amount_end) AS outstanding
FROM (
    SELECT CASE WHEN dla.date IS NULL THEN dp.date ELSE dla.date END AS date
         , COALESCE(loan_amount, 0)                                  AS loan_amount_end
         , COALESCE(payment_amount, 0)                               AS payment_amount_end
    FROM day_loan_amount dla
    FULL JOIN day_payments dp ON dla.date = dp.date
) main
;

CREATE OR REPLACE VIEW loans_pbi AS
SELECT *
FROM loans l
WHERE 1 = 1
  AND l.status NOT IN (1, 8) -- all activated loans
;

CREATE OR REPLACE VIEW loans_pbi AS
SELECT *
FROM payments p
WHERE 1 = 1
  AND (p.status != 9999 OR p.payment_amount = 0) --filtering out invalid payment
;

CREATE OR REPLACE VIEW customers_pbi AS
SELECT *
FROM dim_customers
;

CREATE OR REPLACE VIEW loan_statuses_pbi AS
SELECT *
FROM dim_status
;


CREATE OR REPLACE VIEW clean_loans AS
WITH payment          AS (
    SELECT loan_id
         , COUNT(CASE WHEN p.status = 9999 THEN 1 ELSE NULL END)                            AS failed_payments
         , COUNT(CASE WHEN p.payment_amount = 0 THEN 1 ELSE NULL END)                       AS invalid_payments
         , COUNT(CASE WHEN p.status != 9999 AND p.payment_amount != 0 THEN 1 ELSE NULL END) AS completed_payments
    FROM payments p
    GROUP BY 1
)
   , repayments       AS (
    SELECT l.loan_id
         , origination_date::date + INTERVAL '30 DAYS' AS deadline
         , l.loan_amount
         , l.customer_id
         , SUM(p.payment_amount)                       AS paid_amount
         , MAX(p.payment_date)                         AS last_payment_date
    FROM loans l
    LEFT JOIN payments p ON p.loan_id = l.loan_id
    WHERE 1 = 1
      AND l.status NOT IN (1, 8)                     -- all activated loans
      AND (p.status != 9999 OR p.payment_amount = 0) --filtering out invalid payments
    GROUP BY 1, 2, 3, 4
    ORDER BY 3 DESC
)
   , overdue_paid     AS (
    SELECT l.loan_id
         , EXTRACT(DAY FROM (deadline - last_payment_date::date)) AS days_overdue
    FROM loans l
    LEFT JOIN (
                  SELECT loan_id
                       , last_payment_date
                       , deadline
                  FROM repayments rp
              ) r ON r.loan_id = l.loan_id
    WHERE 1 = 1
      AND last_payment_date > deadline
)
   , overdue_not_paid AS (
    SELECT l.loan_id
         , EXTRACT(DAY FROM (deadline - last_payment_date::date)) AS days_overdue
    FROM loans l
    LEFT JOIN (
                  SELECT loan_id
                       , last_payment_date
                       , deadline
                  FROM repayments p
                  WHERE 1 = 1
                    AND paid_amount = 0
              ) r ON r.loan_id = l.loan_id
    WHERE 1 = 1
      AND last_payment_date > deadline
)
SELECT loan_id                 AS loan_id
     , customer_id             AS customer_id
     , last_payment_date::date AS last_payment
     , deadline::date          AS deadline
     , completed_payments      AS completed_payments
     , failed_payments         AS failed_payments
     , invalid_payments        AS invalid_payments
     , paid_amount             AS paid_amount
     , loan_amount             AS loan_amount
     , remaining_bal           AS remaining_bal
     , repaid_perc             AS repaid_perc
     , days_overdue            AS days_overdue
     , overdue_status          AS overdue_status
FROM (
    SELECT rp.*
         , pp.completed_payments
         , pp.failed_payments
         , pp.invalid_payments
         , (paid_amount - rp.loan_amount)                                                   AS remaining_bal
         , CAST(((paid_amount) / rp.loan_amount) * 100 AS DEC(10, 2)) || '%'                AS repaid_perc
         , CASE WHEN odn.days_overdue IS NULL THEN od.days_overdue ELSE od.days_overdue END AS days_overdue
         , CASE
               WHEN odn.days_overdue IS NOT NULL THEN 'DEFAULTED - OVERDUE'
               WHEN od.days_overdue IS NOT NULL AND odn.days_overdue IS NULL THEN 'FINISHED - OVERDUE'
               ELSE 'NOT OVERDUE' END                                                       AS overdue_status
    FROM repayments rp
    LEFT JOIN payment pp ON pp.loan_id = rp.loan_id
    LEFT JOIN overdue_paid od ON rp.loan_id = od.loan_id
    LEFT JOIN overdue_not_paid odn ON rp.loan_id = odn.loan_id
    WHERE 1 = 1
) main
WHERE 1 = 1

