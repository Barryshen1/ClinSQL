WITH
-- 1. Get all female inpatients aged 48-58
base_admissions AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 48 AND 58
),

-- 2. Find admissions with BOTH T2DM and HF diagnosis
admissions_with_t2dm_hf AS (
  SELECT
    ba.subject_id,
    ba.hadm_id,
    ba.admittime,
    ba.dischtime
  FROM
    base_admissions ba
    JOIN (
      SELECT
        hadm_id,
        MAX(CASE WHEN icd_version = 9 AND (icd_code LIKE '250%' AND (SUBSTR(icd_code,6,1) IN ('0','2')) )
                  OR icd_version = 10 AND icd_code LIKE 'E11%' THEN 1 ELSE 0 END) AS has_t2dm,
        MAX(CASE WHEN icd_version = 9 AND icd_code LIKE '428%' 
                  OR icd_version = 10 AND icd_code LIKE 'I50%' THEN 1 ELSE 0 END) AS has_hf
      FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      GROUP BY
        hadm_id
    ) dx
      ON ba.hadm_id = dx.hadm_id
  WHERE
    dx.has_t2dm = 1
    AND dx.has_hf = 1
),

-- 3. Find first GLP-1 injectable administration per admission
glp1_initiation AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    MIN(emar.charttime) AS first_glp1_time
  FROM
    admissions_with_t2dm_hf adm
    JOIN `physionet-data.mimiciv_3_1_hosp.emar` emar
      ON adm.subject_id = emar.subject_id
      AND adm.hadm_id = emar.hadm_id
  WHERE
    LOWER(emar.medication) LIKE '%exenatide%'
    OR LOWER(emar.medication) LIKE '%liraglutide%'
    OR LOWER(emar.medication) LIKE '%dulaglutide%'
    OR LOWER(emar.medication) LIKE '%semaglutide%'
    OR LOWER(emar.medication) LIKE '%lixisenatide%'
    -- Exclude oral semaglutide
    AND (LOWER(emar.medication) NOT LIKE '%oral%' OR LOWER(emar.medication) NOT LIKE '%tablet%')
  GROUP BY
    adm.subject_id,
    adm.hadm_id
),

-- 4. Mark admissions with initiation in first 72h and/or last 48h
window_flags AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    gi.first_glp1_time,
    CASE
      WHEN gi.first_glp1_time IS NOT NULL
           AND TIMESTAMP_DIFF(gi.first_glp1_time, adm.admittime, HOUR) BETWEEN 0 AND 72
      THEN 1 ELSE 0 END AS initiated_first_72h,
    CASE
      WHEN gi.first_glp1_time IS NOT NULL
           AND TIMESTAMP_DIFF(adm.dischtime, gi.first_glp1_time, HOUR) BETWEEN 0 AND 48
      THEN 1 ELSE 0 END AS initiated_last_48h
  FROM
    admissions_with_t2dm_hf adm
    LEFT JOIN glp1_initiation gi
      ON adm.subject_id = gi.subject_id
      AND adm.hadm_id = gi.hadm_id
)

-- 5. Aggregate rates
SELECT
  COUNT(*) AS n_admissions,
  SUM(initiated_first_72h) AS n_first_72h,
  SUM(initiated_last_48h) AS n_last_48h,
  ROUND(SAFE_DIVIDE(SUM(initiated_first_72h), COUNT(*)) * 100, 2) AS pct_first_72h,
  ROUND(SAFE_DIVIDE(SUM(initiated_last_48h), COUNT(*)) * 100, 2) AS pct_last_48h,
  ROUND(
    ROUND(SAFE_DIVIDE(SUM(initiated_first_72h), COUNT(*)) * 100, 2)
    - ROUND(SAFE_DIVIDE(SUM(initiated_last_48h), COUNT(*)) * 100, 2)
  , 2) AS absolute_difference_pp
FROM
  window_flags;