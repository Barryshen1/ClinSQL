WITH all_icu_stays AS (
  SELECT 
    icu.stay_id,
    icu.subject_id,
    icu.hadm_id,
    icu.intime,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year) AS age_at_icu_admission,
    MAX(CASE WHEN diag.icd_code IN ('518.82', 'J80') THEN 1 ELSE 0 END) AS ards_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON icu.hadm_id = diag.hadm_id
  GROUP BY icu.stay_id, icu.subject_id, icu.hadm_id, icu.intime, p.gender, p.anchor_age, p.anchor_year
),
procedures_in_first_24h AS (
  SELECT 
    p.stay_id,
    COUNT(DISTINCT p.itemid) AS distinct_procedures
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` p
  INNER JOIN all_icu_stays a
    ON p.stay_id = a.stay_id
  WHERE p.starttime >= a.intime
    AND p.starttime <= DATETIME_ADD(a.intime, INTERVAL 24 HOUR)
  GROUP BY p.stay_id
),
icu_with_metrics AS (
  SELECT 
    a.stay_id,
    a.subject_id,
    a.hadm_id,
    a.age_at_icu_admission,
    a.gender,
    a.ards_flag,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_hospital,
    adm.hospital_expire_flag,
    COALESCE(p.distinct_procedures, 0) AS distinct_procedures
  FROM all_icu_stays a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON a.hadm_id = adm.hadm_id
  LEFT JOIN procedures_in_first_24h p
    ON a.stay_id = p.stay_id
)
SELECT 
  'ARDS Group (Female, 84-94)' AS cohort,
  COUNT(*) AS n_icu_stays,
  APPROX_QUANTILES(distinct_procedures, 100)[OFFSET(25)] AS p25_diag_intensity,
  APPROX_QUANTILES(distinct_procedures, 100)[OFFSET(75)] AS p75_diag_intensity,
  APPROX_QUANTILES(distinct_procedures, 100)[OFFSET(95)] AS p95_diag_intensity,
  AVG(los_hospital) AS avg_hospital_los,
  AVG(hospital_expire_flag) AS hospital_mortality_rate
FROM icu_with_metrics
WHERE ards_flag = 1
  AND gender = 'F'
  AND age_at_icu_admission BETWEEN 84 AND 94
UNION ALL
SELECT 
  'General ICU' AS cohort,
  COUNT(*) AS n_icu_stays,
  APPROX_QUANTILES(distinct_procedures, 100)[OFFSET(25)] AS p25_diag_intensity,
  APPROX_QUANTILES(distinct_procedures, 100)[OFFSET(75)] AS p75_diag_intensity,
  APPROX_QUANTILES(distinct_procedures, 100)[OFFSET(95)] AS p95_diag_intensity,
  AVG(los_hospital) AS avg_hospital_los,
  AVG(hospital_expire_flag) AS hospital_mortality_rate
FROM icu_with_metrics;