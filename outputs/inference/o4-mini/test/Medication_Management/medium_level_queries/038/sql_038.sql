WITH cohort AS (
  -- 1. Base cohort: male inpatients, age 57-67
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      USING(subject_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 57 AND 67
),
dx AS (
  -- 2. Identify hadm_id with diabetes
  SELECT DISTINCT hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      USING(icd_code, icd_version)
  WHERE
    LOWER(dd.long_title) LIKE '%diabetes%'
),
hf AS (
  -- 2. Identify hadm_id with acute heart failure
  SELECT DISTINCT hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      USING(icd_code, icd_version)
  WHERE
    LOWER(dd.long_title) LIKE '%heart failure%'
    AND LOWER(dd.long_title) LIKE '%acute%'
),
cohort_dx AS (
  -- 2. Restrict cohort to those with both diagnoses
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime
  FROM
    cohort c
    JOIN dx      USING(hadm_id)
    JOIN hf      USING(hadm_id)
),
glp1_events AS (
  -- 3. Find first GLP-1 prescription per hadm_id
  SELECT
    cd.subject_id,
    cd.hadm_id,
    MIN(p.starttime) AS first_glp1_time,
    cd.admittime,
    cd.dischtime
  FROM
    cohort_dx cd
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
      ON cd.hadm_id = p.hadm_id
  WHERE
    LOWER(p.drug) LIKE '%liraglutide%'
    OR LOWER(p.drug) LIKE '%exenatide%'
    OR LOWER(p.drug) LIKE '%dulaglutide%'
    OR LOWER(p.drug) LIKE '%semaglutide%'
  GROUP BY
    cd.subject_id, cd.hadm_id, cd.admittime, cd.dischtime
),
stats AS (
  -- 4. Classify initiation windows and compute counts
  SELECT
    COUNT(*) AS n_total,
    COUNTIF(first_glp1_time IS NOT NULL) AS n_ever,
    COUNTIF(first_glp1_time <= admittime + INTERVAL 72 HOUR)              AS n_first_72h,
    COUNTIF(first_glp1_time >= dischtime - INTERVAL 24 HOUR)              AS n_final_24h
  FROM
    cohort_dx cd
    LEFT JOIN glp1_events ge
      USING(subject_id, hadm_id, admittime, dischtime)
)
-- 5. Final results
SELECT
  n_total,
  n_ever,
  ROUND(100.0 * n_ever / n_total, 2)          AS prevalence_pct,
  ROUND(100.0 * n_first_72h / n_total, 2)      AS init_first_72h_pct,
  ROUND(100.0 * n_final_24h / n_total, 2)      AS init_final_24h_pct,
  ROUND(100.0 * (n_final_24h - n_first_72h) / n_total, 2)      AS abs_change_pct,
  CASE
    WHEN n_first_72h = 0 THEN NULL
    ELSE ROUND(
           100.0 * ( (n_final_24h / n_total) / (n_first_72h / n_total) - 1 )
         , 2)
  END AS rel_change_pct
FROM stats;