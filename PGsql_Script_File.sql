

--===============================================================
-- PGSQL HR Analytics Project – Cleaned SQL Script
--===============================================================

-- SECTION 1: Split Full Name into First and Last Name
-----------------------------------------------------------------
ALTER TABLE employees
ADD COLUMN first_name TEXT,
ADD COLUMN last_name TEXT;

UPDATE employees
SET first_name = split_part(name, ' ', 1),
    last_name  = substring(name FROM position(' ' IN name));

-- SECTION 2: Refresh Materialized View (if needed)
-
REFRESH MATERIALIZED VIEW hr_attrition_dashboard;

-- SECTION 3: Remove Duplicate Employee Records using CTID
-----------------------------------------------------------------
WITH cte AS (
    SELECT ctid, emp_id,
           ROW_NUMBER() OVER (PARTITION BY emp_id ORDER BY ctid) AS rnk
    FROM employee
)
DELETE FROM employee
WHERE ctid IN (SELECT ctid FROM cte WHERE rnk > 1);

-- SECTION 4: Top 5 Highest Paid Employees per Department
-----------------------------------------------------------------
WITH cte AS (
    SELECT e.first_name || ' ' || e.last_name AS full_name,
           e.salary,
           d.department,
           ROW_NUMBER() OVER(PARTITION BY d.department ORDER BY e.salary DESC) AS sal_rank
    FROM employee e
    JOIN department d ON e.department_id = d.department_id
)
SELECT *
FROM cte
WHERE sal_rank <= 5;

-- SECTION 5: Monthly Attrition %
-----------------------------------------------------------------
WITH cte AS (
    SELECT generate_series(SD, ED, interval '1 month')::date AS cal_mon
    FROM (
        SELECT date_trunc('month', MIN(date_join))::date AS SD,
               date_trunc('month', MAX(date_exit))::date AS ED
        FROM employee
    ) AS gs
),
cte1 AS (
    SELECT cal_mon, COUNT(emp_id) AS active_count
    FROM cte c
    LEFT JOIN employee e
        ON e.date_join <= (cal_mon + interval '1 month - 1 day')
        AND (e.date_exit IS NULL OR e.date_exit >= cal_mon)
    GROUP BY cal_mon
),
cte2 AS (
    SELECT date_trunc('month', date_exit)::date AS doe
    FROM employee
    WHERE date_exit IS NOT NULL
),
cte3 AS (
    SELECT cal_mon, COALESCE(COUNT(doe), 0) AS exit_count
    FROM cte1 c1
    JOIN cte2 c2 ON c1.cal_mon = c2.doe
    GROUP BY c1.cal_mon
)
SELECT cte1.cal_mon, active_count, exit_count,
       COALESCE(ROUND((exit_count::decimal / active_count) * 100, 2), 0) || '%' AS attrition_percent
FROM cte1
LEFT JOIN cte3 ON cte1.cal_mon = cte3.cal_mon;

-- SECTION 6: Average Salary by Department
-----------------------------------------------------------------
SELECT d.department, ROUND(AVG(e.salary), 2) AS avg_salary
FROM employee e
JOIN department d ON e.department_id = d.department_id
GROUP BY d.department
ORDER BY avg_salary;

-- SECTION 7: Salary by Tenure and Department (Combined)
-----------------------------------------------------------------
WITH cte AS (
    SELECT emp_id, date_join, CURRENT_DATE AS curr_date,
           AGE(CURRENT_DATE, date_join) AS complete_tenure,
           CASE
               WHEN EXTRACT(YEAR FROM AGE(CURRENT_DATE, date_join)) <= 5 THEN '0-5 yrs'
               WHEN EXTRACT(YEAR FROM AGE(CURRENT_DATE, date_join)) <= 10 THEN '6-10 yrs'
               WHEN EXTRACT(YEAR FROM AGE(CURRENT_DATE, date_join)) <= 15 THEN '11-15 yrs'
               ELSE '15+ yrs'
           END AS tenure
    FROM employee
)
SELECT c.tenure AS label, ROUND(AVG(e.salary)) AS avg_salary
FROM cte c
JOIN employee e ON c.emp_id = e.emp_id
GROUP BY c.tenure

UNION ALL

SELECT d.department AS label, ROUND(AVG(e.salary), 2) AS avg_salary
FROM employee e
JOIN department d ON e.department_id = d.department_id
GROUP BY d.department
ORDER BY label;

-- SECTION 8: Salary Band Distribution
-----------------------------------------------------------------
SELECT emp_id, first_name, salary,
       CASE
           WHEN salary <= 50000 THEN 'Low'
           WHEN salary <= 100000 THEN 'Middle'
           ELSE 'High'
       END AS salary_band
FROM employee;

-- SECTION 9: Department with Highest Net Gain (Hires - Exits)
-----------------------------------------------------------------
SELECT d.department AS department,
       COUNT(CASE WHEN e.date_join IS NOT NULL THEN 1 END) AS doj,
       COUNT(CASE WHEN e.date_exit IS NOT NULL THEN 1 END) AS doe,
       COUNT(CASE WHEN e.date_join IS NOT NULL THEN 1 END) -
       COUNT(CASE WHEN e.date_exit IS NOT NULL THEN 1 END) AS net_gain
FROM employee e
JOIN department d ON e.department_id = d.department_id
GROUP BY d.department;
