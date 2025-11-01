WITH aki_codes AS (
  SELECT '9' AS icd_version, code AS icd_code
  FROM UNNEST(['584']) AS code
  UNION ALL
  SELECT '10', code
  FROM UNNEST(['N17']) AS code
),
-- Identify hadm_id with AKI diagnosis
aki_hadm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9   AND icd_code LIKE '584%')
     OR (icd_version = 10  AND icd_code LIKE 'N17%')
),
-- Base cohort: male 47–57 inpatients
base_cohort AS (
  SELECT
    pat.subject_id,
    adm.hadm_id,
    pat.anchor_age,
    pat.gender,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    CASE WHEN aki.hadm_id IS NOT NULL THEN 'AKI' ELSE 'Control' END AS cohort
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  LEFT JOIN aki_hadm aki
    ON adm.hadm_id = aki.hadm_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 47 AND 57
),
-- Lab instability score in first 72h
lab_scores AS (
  SELECT
    bc.hadm_id,
    COUNTIF(flag = 'abnormal') AS lab_instability_score
  FROM base_cohort bc
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON bc.hadm_id = le.hadm_id
   AND le.charttime BETWEEN bc.admittime
                        AND DATETIME_ADD(bc.admittime, INTERVAL 72 HOUR)
  GROUP BY bc.hadm_id
),
-- ICU admissions within hospitalization as critical events
icu_flags AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT stay_id) AS icu_count,
    CASE WHEN COUNT(DISTINCT stay_id) > 0 THEN 1 ELSE 0 END AS critical_event_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY hadm_id
),
-- Combine all per-admission outcomes
cohort_measures AS (
  SELECT
    bc.cohort,
    bc.hadm_id,
    COALESCE(ls.lab_instability_score, 0) AS lab_instability_score,
    COALESCE(ifg.critical_event_flag, 0) AS critical_event_flag,
    TIMESTAMP_DIFF(bc.dischtime, bc.admittime, HOUR)/24.0 AS los_days,
    bc.hospital_expire_flag
  FROM base_cohort bc
  LEFT JOIN lab_scores ls
    ON bc.hadm_id = ls.hadm_id
  LEFT JOIN icu_flags ifg
    ON bc.hadm_id = ifg.hadm_id
)
SELECT
  cohort,
  AVG(lab_instability_score) AS mean_72h_lab_instability_score,
  AVG(critical_event_flag)   AS critical_event_rate,
  AVG(los_days)              AS avg_los_days,
  AVG(hospital_expire_flag)  AS inhospital_mortality_rate
FROM cohort_measures
GROUP BY cohort;