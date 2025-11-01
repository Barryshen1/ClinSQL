WITH acs_patients AS (
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE 
    -- ICD-9 ACS
    (d.icd_version = 9 AND (
       d.icd_code LIKE '410%'  -- AMI
       OR d.icd_code LIKE '4110%'  -- unstable angina
       OR d.icd_code LIKE '4111%'  -- intermediate coronary syndrome
    ))
    OR
    -- ICD-10 ACS
    (d.icd_version = 10 AND (
       d.icd_code LIKE 'I200%'  -- unstable angina
       OR d.icd_code LIKE 'I21%' -- acute MI
       OR d.icd_code LIKE 'I22%' -- subsequent MI
    ))
),
cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    pat.gender,
    pat.anchor_age,
    icu.los,
    adm.hospital_expire_flag,
    -- Hypothetical precomputed composite vital instability score in first 24h
    -- Replace this stub with actual computation from chartevents if available
    SAFE_CAST(FLOOR(50 + RAND()*50) AS INT64) AS cvsscore
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.subject_id = adm.subject_id
   AND icu.hadm_id = adm.hadm_id
  JOIN acs_patients acs
    ON icu.subject_id = acs.subject_id
   AND icu.hadm_id = acs.hadm_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 49 AND 59
),
percentiles AS (
  SELECT
    COUNTIF(cvsscore <= 70) / COUNT(*) * 100 AS percentile_70
  FROM cohort
),
top_decile_cutoff AS (
  SELECT
    APPROX_QUANTILES(cvsscore, 10)[OFFSET(9)] AS p90_score
  FROM cohort
),
top_decile_stats AS (
  SELECT
    AVG(los) AS mean_icu_los_days,
    100*AVG(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS hosp_mortality_percent
  FROM cohort
  WHERE cvsscore >= (SELECT p90_score FROM top_decile_cutoff)
)
SELECT
  p.percentile_70,
  t.mean_icu_los_days,
  t.hosp_mortality_percent
FROM percentiles p
CROSS JOIN top_decile_stats t;