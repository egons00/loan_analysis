--Defaulted loans
-- 4217496
-- 4218402
-- 4219781

--
-- No descriptions on the data set, no payment status information, no defined amount currency rates
-- Assumptions that I made:
-- All currency is in EUR, loan_amount as a whole number, failed payments - status = 9999, invalid payments: payment_amount = 0


--Main table
CREATE TEMP TABLE loan_data AS
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
;

--identify loans that are in overdue for more than 90 days
SELECT *
FROM loan_data
WHERE 1=1
AND days_overdue < -90

--Summary on total count of customers with defaulted loans
SELECT
COUNT(DISTINCT customer_id) AS count_customers,
AVG(loan_amount)            AS avg_loan_amount
FROM loan_data
WHERE 1=1
AND overdue_status = 'DEFAULTED - OVERDUE'



-- ///////////
--Customers with multiple loans
--no customers which have had 2 active loans
WITH loans AS (
SELECT customer_id
     , COUNT(DISTINCT ld.loan_id) AS loan_count
     , SUM(loan_amount)          AS total_amount
     , SUM(remaining_bal)               AS sum_paid
FROM loan_data ld
WHERE 1 = 1
GROUP BY 1
)
SELECT
customer_id,
       loan_count,
       total_amount,
       sum_paid
FROM loans
GROUP BY 1,2,3,4
HAVING loan_count > 1

--1 customer with 2 rejected loans
SELECT customer_id
     , COUNT(DISTINCT loan_id) AS loans_c
FROM loans
GROUP BY 1
HAVING COUNT(DISTINCT loan_id) > 1

SELECT *
FROM loans
WHERE customer_id = 1744016



-- /////////////
--Find top 10 customers with highest surplus on customer level
SELECT customer_id
     , SUM(remaining_bal) AS surplus
FROM loan_data
WHERE 1 = 1
  AND remaining_bal > 0
GROUP BY 1
ORDER BY 2 DESC
LIMIT 10
