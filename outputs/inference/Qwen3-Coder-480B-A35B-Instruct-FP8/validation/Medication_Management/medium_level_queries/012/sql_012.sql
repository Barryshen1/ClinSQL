WITH target_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 50 AND 60
),

target_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN target_patients tp ON a.subject_id = tp.subject_id
  WHERE DATETIME_DIFF(a.dischtime, a.admittime, HOUR) >= 72
),

t2dm_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_code LIKE 'E11%'
    AND icd_version = 10
),

hf_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_code LIKE 'I50%'
    AND icd_version = 10
),

qualifying_admissions AS (
  SELECT ta.*
  FROM target_admissions ta
  JOIN t2dm_admissions t2dm ON ta.hadm_id = t2dm.hadm_id
  JOIN hf_admissions hf ON ta.hadm_id = hf.hadm_id
),

glp1_medications AS (
  SELECT *
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE LOWER(drug) IN (
    'liraglutide', 'exenatide', 'dulaglutide', 'semaglutide',
    'lixisenatide', 'albiglutide'
  )
),

admission_glp1_flags AS (
  SELECT
    qa.hadm_id,
    MIN(glp.starttime) AS first_glp1_start,
    MAX(glp.stoptime) AS last_glp1_stop,
    -- First 12-hour initiation
    LOGICAL_OR(
      glp.starttime BETWEEN qa.admittime AND DATETIME_ADD(qa.admittime, INTERVAL 12 HOUR)
    ) AS initiated_first_12hr,
    -- Final 72-hour use
    LOGICAL_OR(
      glp.starttime <= qa.dischtime
      AND COALESCE(glp.stoptime, qa.dischtime) >= DATETIME_SUB(qa.dischtime, INTERVAL 72 HOUR)
    ) AS used_last_72hr
  FROM qualifying_admissions qa
  LEFT JOIN glp1_medications glp USING (hadm_id)
  GROUP BY qa.hadm_id
)

SELECT
  COUNT(*) AS total_admissions,
  SUM(IF(initiated_first_12hr, 1, 0)) AS initiated_first_12hr_count,
  SUM(IF(used_last_72hr, 1, 0)) AS used_last_72hr_count,
  ROUND(
    100 * SUM(IF(initiated_first_12hr, 1, 0)) / COUNT(*),
    2
  ) AS first_12hr_initiation_pct,
  ROUND(
    100 * SUM(IF(used_last_72hr, 1, 0)) / COUNT(*),
    2
  ) AS final_72hr_prevalence_pct,
  ROUND(
    100 * (
      SUM(IF(used_last_72hr, 1, 0)) - SUM(IF(initiated_first_12hr, 1, 0))
    ) / COUNT(*),
    2
  ) AS net_pct_point_change
FROM admission_glp1_flags;