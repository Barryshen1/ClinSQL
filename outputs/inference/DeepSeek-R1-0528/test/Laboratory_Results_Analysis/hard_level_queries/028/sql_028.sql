WITH
-- ICH Cohort: Female, age 74-84, with ICH diagnosis
ich_cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE
    pat.gender = 'F'
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 74 AND 84
    AND (
      (diag.icd_version = 10 AND diag.icd_code LIKE 'I61%')
      OR (diag.icd_version = 10 AND diag.icd_code LIKE 'I62%')
      OR (diag.icd_version = 9 AND diag.icd_code IN ('431', '4320', '4321', '4329'))
    )
  GROUP BY adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime, adm.hospital_expire_flag
),

-- Control Cohort: Female, age 74-84, without ICH
control_cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 74 AND 84
    AND adm.hadm_id NOT IN (SELECT hadm_id FROM ich_cohort)  -- Exclude ICH patients
  GROUP BY adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime, adm.hospital_expire_flag
),

-- Distinct abnormal labs in first 72h for ICH cohort
ich_labs AS (
  SELECT
    ich.hadm_id,
    COUNT(DISTINCT le.itemid) AS distinct_abnormal_labs
  FROM ich_cohort ich
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON ich.hadm_id = le.hadm_id
    AND le.charttime BETWEEN ich.admittime AND DATETIME_ADD(ich.admittime, INTERVAL 72 HOUR)
    AND le.flag IS NOT NULL AND le.flag != 'normal'  -- Abnormal flags only
  GROUP BY ich.hadm_id
),

-- Distinct abnormal labs in first 72h for control cohort
control_labs AS (
  SELECT
    ctrl.hadm_id,
    COUNT(DISTINCT le.itemid) AS distinct_abnormal_labs
  FROM control_cohort ctrl
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON ctrl.hadm_id = le.hadm_id
    AND le.charttime BETWEEN ctrl.admittime AND DATETIME_ADD(ctrl.admittime, INTERVAL 72 HOUR)
    AND le.flag IS NOT NULL AND le.flag != 'normal'
  GROUP BY ctrl.hadm_id
),

-- Combine ICH cohort with lab counts (default 0 if no labs)
ich_with_labs AS (
  SELECT
    ich.*,
    COALESCE(il.distinct_abnormal_labs, 0) AS distinct_abnormal_labs
  FROM ich_cohort ich
  LEFT JOIN ich_labs il ON ich.hadm_id = il.hadm_id
),

-- Combine control cohort with lab counts (default 0 if no labs)
control_with_labs AS (
  SELECT
    ctrl.*,
    COALESCE(cl.distinct_abnormal_labs, 0) AS distinct_abnormal_labs
  FROM control_cohort ctrl
  LEFT JOIN control_labs cl ON ctrl.hadm_id = cl.hadm_id
),

-- Assign quintiles based on distinct abnormal lab count for ICH
ich_quintiles AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY distinct_abnormal_labs) AS quintile
  FROM ich_with_labs
)

-- Combined output for both parts
SELECT 
  'Part1' AS part,  -- Identifier for mortality/LOS by quintile
  quintile,
  NULL AS cohort,   -- Not applicable for Part1
  COUNT(*) AS num_patients,
  AVG(hospital_expire_flag) * 100 AS mortality_rate_percent,
  AVG(los_days) AS mean_los_days,
  NULL AS avg_distinct_abnormal_labs  -- Not applicable for Part1
FROM ich_quintiles
GROUP BY quintile

UNION ALL

-- Part 2: Critical lab rate comparison (ICH vs Control)
SELECT 
  'Part2' AS part,  -- Identifier for lab comparison
  NULL AS quintile, -- Not applicable for Part2
  cohort,
  NULL AS num_patients,              -- Not applicable
  NULL AS mortality_rate_percent,    -- Not applicable
  NULL AS mean_los_days,             -- Not applicable
  avg_distinct_abnormal_labs
FROM (
  SELECT 
    'ICH' AS cohort, 
    AVG(distinct_abnormal_labs) AS avg_distinct_abnormal_labs
  FROM ich_with_labs
  UNION ALL
  SELECT 
    'Control' AS cohort, 
    AVG(distinct_abnormal_labs) AS avg_distinct_abnormal_labs
  FROM control_with_labs
) AS lab_compare

-- Order results: Part1 first (by quintile), then Part2 (ICH before Control)
ORDER BY 
  part, 
  quintile, 
  CASE 
    WHEN cohort = 'ICH' THEN 1 
    WHEN cohort = 'Control' THEN 2 
    ELSE NULL 
  END;