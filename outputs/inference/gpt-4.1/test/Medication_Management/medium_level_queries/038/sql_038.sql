WITH cohort AS (
  -- Select male inpatients age 57-67 with diabetes AND acute HF in same admission
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  -- Diabetes diagnosis
  JOIN (
    SELECT DISTINCT hadm_id
    FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd
    WHERE
      (icd_version = 9 AND icd_code LIKE '250%')
      OR (icd_version = 10 AND icd_code LIKE 'E1%')
  ) d1 ON a.hadm_id = d1.hadm_id
  -- Acute HF diagnosis
  JOIN (
    SELECT DISTINCT hadm_id
    FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd
    WHERE
      (icd_version = 9 AND (icd_code LIKE '4280%' OR icd_code LIKE '4281%' OR icd_code LIKE '4282%' OR icd_code LIKE '4283%' OR icd_code LIKE '4284%' OR icd_code LIKE '4289%'))
      OR (icd_version = 10 AND icd_code LIKE 'I50%')
  ) d2 ON a.hadm_id = d2.hadm_id
  WHERE
    p.anchor_age BETWEEN 57 AND 67
    AND p.gender = 'M'
),

glp1_rx AS (
  -- Find first GLP-1 prescription or pharmacy event per admission
  SELECT
    hadm_id,
    MIN(starttime) AS first_glp1_time
  FROM (
    SELECT
      hadm_id,
      starttime
    FROM physionet-data.mimiciv_3_1_hosp.prescriptions
    WHERE LOWER(drug) LIKE '%exenatide%'
      OR LOWER(drug) LIKE '%liraglutide%'
      OR LOWER(drug) LIKE '%dulaglutide%'
      OR LOWER(drug) LIKE '%semaglutide%'
      OR LOWER(drug) LIKE '%lixisenatide%'
      OR LOWER(drug) LIKE '%albiglutide%'
    UNION ALL
    SELECT
      hadm_id,
      starttime
    FROM physionet-data.mimiciv_3_1_hosp.pharmacy
    WHERE LOWER(medication) LIKE '%exenatide%'
      OR LOWER(medication) LIKE '%liraglutide%'
      OR LOWER(medication) LIKE '%dulaglutide%'
      OR LOWER(medication) LIKE '%semaglutide%'
      OR LOWER(medication) LIKE '%lixisenatide%'
      OR LOWER(medication) LIKE '%albiglutide%'
  )
  GROUP BY hadm_id
),

final AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.anchor_age,
    c.gender,
    c.admittime,
    c.dischtime,
    rx.first_glp1_time,
    -- Prevalence: any GLP-1 use
    CASE WHEN rx.first_glp1_time IS NOT NULL THEN 1 ELSE 0 END AS glp1_prevalent,
    -- Initiation in first 72h
    CASE WHEN rx.first_glp1_time IS NOT NULL AND TIMESTAMP_DIFF(rx.first_glp1_time, c.admittime, HOUR) BETWEEN 0 AND 72 THEN 1 ELSE 0 END AS glp1_init_72h,
    -- Initiation in final 24h
    CASE WHEN rx.first_glp1_time IS NOT NULL AND TIMESTAMP_DIFF(c.dischtime, rx.first_glp1_time, HOUR) BETWEEN 0 AND 24 THEN 1 ELSE 0 END AS glp1_init_final24h
  FROM cohort c
  LEFT JOIN glp1_rx rx
    ON c.hadm_id = rx.hadm_id
)

-- Aggregate and calculate percentages in a subquery, then reference them in outer SELECT
SELECT
  n_admissions,
  n_glp1_prevalent,
  prevalence_pct,
  n_init_72h,
  init_72h_pct,
  n_init_final24h,
  init_final24h_pct,
  -- Absolute and relative change
  ROUND(init_final24h_pct - init_72h_pct, 2) AS absolute_change_pct,
  CASE WHEN init_72h_pct > 0 THEN ROUND(init_final24h_pct / init_72h_pct, 2) ELSE NULL END AS relative_change
FROM (
  SELECT
    COUNT(*) AS n_admissions,
    SUM(glp1_prevalent) AS n_glp1_prevalent,
    ROUND(100 * SUM(glp1_prevalent) / COUNT(*), 2) AS prevalence_pct,
    SUM(glp1_init_72h) AS n_init_72h,
    ROUND(100 * SUM(glp1_init_72h) / COUNT(*), 2) AS init_72h_pct,
    SUM(glp1_init_final24h) AS n_init_final24h,
    ROUND(100 * SUM(glp1_init_final24h) / COUNT(*), 2) AS init_final24h_pct
  FROM final
);