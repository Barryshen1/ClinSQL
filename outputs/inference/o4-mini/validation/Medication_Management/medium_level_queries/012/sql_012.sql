WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    -- Age and gender filter
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    -- Admission duration >= 72 hours
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 72
    -- Ensure T2DM and heart failure diagnoses in this admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND d.icd_code LIKE 'E11%'  -- Type 2 diabetes
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND d.icd_code LIKE 'I50%'  -- Heart failure
    )
),

glp1_rx AS (
  -- Identify GLP-1 prescriptions in the first 72 hours
  SELECT
    c.hadm_id,
    -- Flag for any Rx ≤ admit + 12h
    MAX(CASE WHEN rx.starttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 12 HOUR) THEN 1 ELSE 0 END) AS init_12h,
    -- Flag for any Rx ≤ admit + 72h
    MAX(CASE WHEN rx.starttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END) AS init_72h
  FROM
    cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` rx
      ON rx.hadm_id = c.hadm_id
      AND LOWER(rx.drug) IN ('exenatide','liraglutide','dulaglutide','semaglutide')
      -- Only consider prescriptions that start within 72h
      AND rx.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
  GROUP BY
    c.hadm_id
)

SELECT
  COUNT(*) AS total_admissions,
  SUM(init_12h) AS count_init_12h,
  SUM(init_72h) AS count_init_72h,
  ROUND(100.0 * SUM(init_12h) / COUNT(*), 1) AS pct_init_12h,
  ROUND(100.0 * SUM(init_72h) / COUNT(*), 1) AS pct_init_72h,
  ROUND(
    100.0 * SUM(init_72h) / COUNT(*) 
    - 100.0 * SUM(init_12h) / COUNT(*)
  , 1) AS net_pct_point_change
FROM
  glp1_rx;