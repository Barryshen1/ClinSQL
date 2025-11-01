WITH asthma_dx AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  WHERE ( (di.icd_version = 9 AND di.icd_code LIKE '493%')
       OR (di.icd_version = 10 AND di.icd_code LIKE 'J45%') )
),
icu_female_aged AS (
  SELECT icu.subject_id, icu.hadm_id, icu.stay_id,
         p.anchor_age, p.gender,
         icu.intime, icu.outtime, icu.los,
         a.hospital_expire_flag,
         CASE WHEN adx.subject_id IS NOT NULL THEN 'Asthma' ELSE 'Control' END AS cohort
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON icu.hadm_id = a.hadm_id
  LEFT JOIN asthma_dx adx
    ON icu.subject_id = adx.subject_id
   AND icu.hadm_id = adx.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 83 AND 93
),
instability_item AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) = 'instability score'
),
instability_values AS (
  SELECT ie.cohort, ie.stay_id, ie.los, ie.hospital_expire_flag, ce.valuenum
  FROM icu_female_aged ie
  JOIN instability_item di
    ON TRUE
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ie.stay_id = ce.stay_id
   AND ce.itemid = di.itemid
   AND ce.valuenum IS NOT NULL
   AND ce.charttime BETWEEN ie.intime AND TIMESTAMP_ADD(ie.intime, INTERVAL 72 HOUR)
)
SELECT
  cohort,
  COUNT(DISTINCT stay_id) AS n_stays,
  STDDEV_SAMP(valuenum) AS instability_sd,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] AS p25_instability,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] AS p50_instability,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS p75_instability,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(95)] AS p95_instability,
  AVG(los) AS avg_icu_los,
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_icu_los,
  AVG(CAST(hospital_expire_flag AS INT64)) AS hospital_mortality_rate
FROM instability_values
GROUP BY cohort
ORDER BY cohort;