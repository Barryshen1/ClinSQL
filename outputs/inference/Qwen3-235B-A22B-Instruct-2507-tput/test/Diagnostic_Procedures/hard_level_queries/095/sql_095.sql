WITH cohort AS (
  SELECT DISTINCT icu.subject_id, icu.hadm_id, icu.stay_id, icu.intime, icu.los AS icu_los, adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON icu.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
    ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 79 AND 89
    AND LOWER(d_diag.long_title) LIKE '%pulmonary embolism%'
),
all_icu AS (
  SELECT icu.subject_id, icu.hadm_id, icu.stay_id, icu.intime, icu.los AS icu_los, adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
),
combined_cohorts AS (
  SELECT 'PE 79-89 M' AS group_name, subject_id, hadm_id, stay_id, intime, icu_los, hospital_expire_flag
  FROM cohort
  UNION ALL
  SELECT 'All ICU' AS group_name, subject_id, hadm_id, stay_id, intime, icu_los, hospital_expire_flag
  FROM all_icu
),
lab_counts AS (
  SELECT 
    cc.group_name,
    cc.stay_id,
    cc.icu_los,
    cc.hospital_expire_flag,
    COUNT(lab.labevent_id) AS dus  -- diagnostic utilization score = number of lab tests in first 24h
  FROM combined_cohorts cc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` lab
    ON cc.hadm_id = lab.hadm_id
    AND lab.charttime >= cc.intime
    AND lab.charttime < DATETIME_ADD(cc.intime, INTERVAL 24 HOUR)
  GROUP BY cc.group_name, cc.stay_id, cc.icu_los, cc.hospital_expire_flag
)
SELECT
  group_name,
  APPROX_QUANTILES(dus, 1000)[OFFSET(750)] AS dus_75th,  -- 75th percentile
  APPROX_QUANTILES(icu_los, 1000)[OFFSET(500)] AS median_los,
  AVG(hospital_expire_flag) AS mortality_rate
FROM lab_counts
GROUP BY group_name
ORDER BY group_name;