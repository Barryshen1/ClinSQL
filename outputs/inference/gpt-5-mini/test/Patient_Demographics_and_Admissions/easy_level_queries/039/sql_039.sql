WITH pneumonia_admissions AS (
  -- Admissions with a diagnosis whose description mentions "pneumonia"
  SELECT DISTINCT d_icd.subject_id, d_icd.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_icd
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d_icd.icd_code = dd.icd_code
   AND d_icd.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%pneumonia%'
),

cohort_admissions AS (
  -- Restrict to male patients aged 43-53 (inclusive)
  SELECT pa.subject_id, pa.hadm_id
  FROM pneumonia_admissions pa
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON pa.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
),

first_icustays_per_admission AS (
  -- For each subject + hadm, pick the first ICU stay (earliest intime)
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    ROW_NUMBER() OVER (PARTITION BY i.subject_id, i.hadm_id ORDER BY i.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN cohort_admissions ca
    ON i.subject_id = ca.subject_id
   AND i.hadm_id = ca.hadm_id
)

SELECT
  -- Approximate 25th percentile of ICU LOS (days) across the selected first ICU stays
  APPROX_QUANTILES(los, 100)[OFFSET(25)] AS icu_los_25th_percentile_days,
  COUNT(*) AS sample_size
FROM first_icustays_per_admission
WHERE rn = 1
  AND los IS NOT NULL;