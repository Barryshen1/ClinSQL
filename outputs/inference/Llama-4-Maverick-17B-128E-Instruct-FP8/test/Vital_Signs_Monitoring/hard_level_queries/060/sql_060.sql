WITH cohort AS (
  SELECT p.subject_id, ie.hadm_id, ie.stay_id, ie.intime,
         CASE 
           WHEN EXISTS (
             SELECT 1
             FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
             WHERE di.hadm_id = ie.hadm_id AND di.icd_version = 10 AND di.icd_code IN ('E871')
           ) THEN 1 
           ELSE 0 
         END AS hhs
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie ON p.subject_id = ie.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 78 AND 88
),
vital_signs AS (
  SELECT c.stay_id, ce.valuenum, 
         CASE WHEN ce.itemid IN ( 
           220050,  -- Heart Rate
           220179,  -- Respiratory Rate
           220052  -- SpO2
         ) THEN 1 ELSE 0 END AS is_vital
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON c.stay_id = ce.stay_id
  WHERE ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
),
instability_score AS (
  SELECT stay_id, AVG(valuenum) AS mean_abnormal_vital_burden
  FROM vital_signs
  WHERE is_vital = 1
  GROUP BY stay_id
),
los AS (
  SELECT stay_id, DATETIME_DIFF(outtime, intime, HOUR) AS icu_los
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
mortality AS (
  SELECT ie.stay_id, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON ie.hadm_id = a.hadm_id
)
SELECT 
  hhs,
  APPROX_QUANTILES(mean_abnormal_vital_burden, 100)[OFFSET(25)] AS q1_abnormal_vital,
  APPROX_QUANTILES(mean_abnormal_vital_burden, 100)[OFFSET(50)] AS median_abnormal_vital,
  APPROX_QUANTILES(mean_abnormal_vital_burden, 100)[OFFSET(75)] AS q3_abnormal_vital,
  APPROX_QUANTILES(icu_los, 100)[OFFSET(25)] AS q1_icu_los,
  APPROX_QUANTILES(icu_los, 100)[OFFSET(50)] AS median_icu_los,
  APPROX_QUANTILES(icu_los, 100)[OFFSET(75)] AS q3_icu_los,
  AVG(hospital_expire_flag) AS mortality_rate
FROM cohort c
LEFT JOIN instability_score isc ON c.stay_id = isc.stay_id
LEFT JOIN los ON c.stay_id = los.stay_id
LEFT JOIN mortality m ON c.stay_id = m.stay_id
GROUP BY hhs
ORDER BY hhs;