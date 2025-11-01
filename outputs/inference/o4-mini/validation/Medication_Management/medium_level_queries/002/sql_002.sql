WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      USING(subject_id)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    -- hospital stay >= 48 hours
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 48
),

glp1_events AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    -- flag if any GLP-1 in first 48h
    MAX(CASE
      WHEN pr.starttime BETWEEN c.admittime 
                            AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
      THEN 1 ELSE 0
    END) AS first48_flag,
    -- flag if any GLP-1 in last 12h
    MAX(CASE
      WHEN pr.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR)
                            AND c.dischtime
      THEN 1 ELSE 0
    END) AS last12_flag
  FROM
    cohort AS c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
      ON pr.hadm_id = c.hadm_id
      AND pr.subject_id = c.subject_id
      -- injectable GLP-1 agonists
      AND LOWER(pr.drug) IN (
        'liraglutide', 'exenatide', 'dulaglutide',
        'semaglutide', 'albiglutide', 'lixisenatide'
      )
      -- ensure injectable route
      AND (
        LOWER(pr.route) LIKE '%subcut%' OR
        LOWER(pr.route) LIKE '%inject%'
      )
  GROUP BY
    c.subject_id,
    c.hadm_id
)

SELECT
  COUNT(1) AS total_patients,
  100.0 * SUM(first48_flag) / COUNT(1) AS pct_first48,
  100.0 * SUM(last12_flag) / COUNT(1) AS pct_last12,
  100.0 * ABS( SUM(first48_flag) - SUM(last12_flag) ) / COUNT(1)
    AS absolute_pp_difference
FROM
  glp1_events;