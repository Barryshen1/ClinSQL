WITH cohort AS (
  -- Female inpatients aged 50-60 with diabetes AND heart failure
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  -- Age and gender filter
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND a.hospital_expire_flag = 0 -- exclude in-hospital deaths if desired
    AND EXISTS (
      -- Diabetes diagnosis
      SELECT 1 FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d1
      WHERE d1.hadm_id = a.hadm_id
        AND (
          (d1.icd_version = 9 AND d1.icd_code LIKE '250%')
          OR (d1.icd_version = 10 AND d1.icd_code BETWEEN 'E08' AND 'E13')
        )
    )
    AND EXISTS (
      -- Heart failure diagnosis
      SELECT 1 FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d2
      WHERE d2.hadm_id = a.hadm_id
        AND (
          (d2.icd_version = 9 AND d2.icd_code LIKE '428%')
          OR (d2.icd_version = 10 AND d2.icd_code LIKE 'I50%')
        )
    )
),

glp1_emar AS (
  -- Identify GLP-1 injectable administrations
  SELECT
    e.subject_id,
    e.hadm_id,
    MIN(e.charttime) AS first_admin_time
  FROM physionet-data.mimiciv_3_1_hosp.emar e
  WHERE LOWER(e.medication) LIKE '%liraglutide%'
     OR LOWER(e.medication) LIKE '%semaglutide%'
     OR LOWER(e.medication) LIKE '%exenatide%'
     OR LOWER(e.medication) LIKE '%dulaglutide%'
     OR LOWER(e.medication) LIKE '%albiglutide%'
     OR LOWER(e.medication) LIKE '%glp-1%'
  GROUP BY e.subject_id, e.hadm_id
),

timing AS (
  -- Classify initiation timing for each admission
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    TIMESTAMP_DIFF(c.dischtime, c.admittime, HOUR) AS adm_hours,
    g.first_admin_time,
    CASE
      WHEN g.first_admin_time IS NULL THEN 'none'
      WHEN g.first_admin_time <= TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
        THEN 'first72h'
      WHEN g.first_admin_time >= TIMESTAMP_SUB(c.dischtime, INTERVAL 72 HOUR)
        THEN 'final72h'
      ELSE 'other'
    END AS initiation_window
  FROM cohort c
  LEFT JOIN glp1_emar g
    ON c.subject_id = g.subject_id AND c.hadm_id = g.hadm_id
  WHERE TIMESTAMP_DIFF(c.dischtime, c.admittime, HOUR) >= 144 -- at least 6 days
),

summary AS (
  SELECT
    COUNT(*) AS n_admissions,
    COUNTIF(initiation_window = 'first72h') AS n_first72h,
    COUNTIF(initiation_window = 'final72h') AS n_final72h
  FROM timing
)

SELECT
  n_admissions,
  n_first72h,
  n_final72h,
  n_final72h - n_first72h AS absolute_change,
  SAFE_DIVIDE(n_final72h - n_first72h, n_first72h) AS relative_change
FROM summary;