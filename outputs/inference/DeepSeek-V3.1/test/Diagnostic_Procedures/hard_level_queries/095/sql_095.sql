WITH target_cohort AS (
  SELECT DISTINCT
    ie.subject_id, 
    ie.hadm_id, 
    ie.stay_id,
    -- Count distinct lab items in first 24h of ICU stay
    COUNT(DISTINCT le.itemid) AS num_labs,
    ie.los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON ie.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
    ON ie.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON ie.hadm_id = a.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le 
    ON ie.hadm_id = le.hadm_id 
    AND le.charttime >= ie.intime 
    AND le.charttime < DATETIME_ADD(ie.intime, INTERVAL 24 HOUR)
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 79 AND 89
    AND (
      (di.icd_version = 9 AND di.icd_code LIKE '415.1%') 
      OR (di.icd_version = 10 AND di.icd_code LIKE 'I26%')
    )
  GROUP BY ie.subject_id, ie.hadm_id, ie.stay_id, ie.los, a.hospital_expire_flag
),
general_population AS (
  SELECT 
    ie.subject_id, 
    ie.hadm_id, 
    ie.stay_id,
    a.hospital_expire_flag,
    ie.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON ie.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON ie.hadm_id = a.hadm_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 79 AND 89
)
SELECT
  APPROX_QUANTILES(tc.num_labs, 100)[OFFSET(75)] AS p75_diagnostic_utilization,
  APPROX_QUANTILES(tc.los, 100)[OFFSET(50)] AS target_median_icu_los,
  AVG(CAST(tc.hospital_expire_flag AS FLOAT64)) AS target_mortality_rate,
  (SELECT APPROX_QUANTILES(los, 100)[OFFSET(50)] FROM general_population) AS general_median_icu_los,
  (SELECT AVG(CAST(hospital_expire_flag AS FLOAT64)) FROM general_population) AS general_mortality_rate
FROM target_cohort tc;