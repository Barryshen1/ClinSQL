WITH base_admissions AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime, 
    adm.deathtime,
    adm.hospital_expire_flag,
    pat.gender,
    pat.anchor_age,
    pat.anchor_year,
    pat.dod,
    anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
),

hemorrhage_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code IN ('430','431','432','4320','4321','4329'))
    OR 
    (icd_version = 10 AND icd_code IN ('I60','I61','I62'))
),

with_outcomes AS (
  SELECT 
    ba.*,
    CASE WHEN ha.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS hemorrhage_flag,
    -- 90-day mortality flag
    CASE 
      WHEN dod IS NOT NULL AND DATE_DIFF(CAST(dod AS DATE), CAST(admittime AS DATE), DAY) <= 90 THEN 1
      WHEN deathtime IS NOT NULL AND DATE_DIFF(CAST(deathtime AS DATE), CAST(admittime AS DATE), DAY) <= 90 THEN 1
      ELSE 0 
    END AS mortality_90d,
    -- LOS in days for survivors (NULL if died in hospital)
    CASE 
      WHEN hospital_expire_flag = 0 THEN DATE_DIFF(CAST(dischtime AS DATE), CAST(admittime AS DATE), DAY)
      ELSE NULL 
    END AS survivor_los
  FROM base_admissions ba
  LEFT JOIN hemorrhage_admissions ha 
    ON ba.hadm_id = ha.hadm_id
  WHERE ba.age_at_admission BETWEEN 44 AND 54
),

hemorrhage_group AS (
  SELECT 
    'Intracranial Hemorrhage' AS cohort,
    COUNT(*) AS num_admissions,
    AVG(mortality_90d) * 100 AS mortality_90d_rate,
    APPROX_QUANTILES(survivor_los, 4) AS los_quantiles  -- Removed invalid IGNORE NULLS
  FROM with_outcomes
  WHERE hemorrhage_flag = 1
),

all_group AS (
  SELECT 
    'All Female 44-54' AS cohort,
    COUNT(*) AS num_admissions,
    AVG(mortality_90d) * 100 AS mortality_90d_rate,
    APPROX_QUANTILES(survivor_los, 4) AS los_quantiles  -- Removed invalid IGNORE NULLS
  FROM with_outcomes
)

SELECT 
  cohort,
  num_admissions,
  ROUND(mortality_90d_rate, 2) AS mortality_90d_rate_percent,
  los_quantiles[OFFSET(2)] AS median_survivor_los_days,
  los_quantiles[OFFSET(1)] AS q1_survivor_los_days,
  los_quantiles[OFFSET(3)] AS q3_survivor_los_days,
  los_quantiles[OFFSET(3)] - los_quantiles[OFFSET(1)] AS iqr_survivor_los_days
FROM hemorrhage_group
UNION ALL
SELECT 
  cohort,
  num_admissions,
  ROUND(mortality_90d_rate, 2) AS mortality_90d_rate_percent,
  los_quantiles[OFFSET(2)] AS median_survivor_los_days,
  los_quantiles[OFFSET(1)] AS q1_survivor_los_days,
  los_quantiles[OFFSET(3)] AS q3_survivor_los_days,
  los_quantiles[OFFSET(3)] - los_quantiles[OFFSET(1)] AS iqr_survivor_los_days
FROM all_group;