WITH surgical_pts AS (
  -- Identify female surgical inpatients age 70–80
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    -- require at least one procedure to define a surgical admission
    JOIN (
      SELECT DISTINCT hadm_id, subject_id
      FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
    ) proc
      ON a.hadm_id = proc.hadm_id
      AND a.subject_id = proc.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
),
categorized AS (
  -- Assign discharge category and filter to the three of interest
  SELECT
    hadm_id,
    los,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN UPPER(discharge_location) LIKE '%HOME%' THEN 'Home'
      WHEN UPPER(discharge_location) LIKE '%SNF%'
        OR UPPER(discharge_location) LIKE '%REHAB%'
        OR UPPER(discharge_location) LIKE '%LTACH%' THEN 'Facility'
      ELSE NULL
    END AS discharge_category
  FROM surgical_pts
  WHERE
    -- keep only the three specified categories
    hospital_expire_flag = 1
    OR UPPER(discharge_location) LIKE '%HOME%'
    OR UPPER(discharge_location) LIKE '%SNF%'
    OR UPPER(discharge_location) LIKE '%REHAB%'
    OR UPPER(discharge_location) LIKE '%LTACH%'
),
counts AS (
  -- Compute counts by discharge category
  SELECT
    discharge_category,
    COUNT(*) AS n_total_category,
    SUM(CASE WHEN los >= 7 THEN 1 ELSE 0 END) AS n_ge_7,
    SUM(CASE WHEN los >= 14 THEN 1 ELSE 0 END) AS n_ge_14
  FROM categorized
  GROUP BY discharge_category
),
overall AS (
  -- Compute overall cohort size
  SELECT COUNT(*) AS n_overall
  FROM categorized
)
-- Final: proportions relative to the overall cohort
SELECT
  c.discharge_category,
  c.n_total_category,
  c.n_ge_7,
  c.n_ge_14,
  ROUND(c.n_ge_7    / o.n_overall, 4) AS prop_ge_7,
  ROUND(c.n_ge_14   / o.n_overall, 4) AS prop_ge_14
FROM counts c
CROSS JOIN overall o
ORDER BY
  CASE c.discharge_category
    WHEN 'In-hospital death' THEN 1
    WHEN 'Home'              THEN 2
    WHEN 'Facility'          THEN 3
    ELSE 4
  END;