WITH
-- Females aged 82-92
eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 82 AND 92
),

-- Admissions with AKI (ICD-10: N17.*)
aki_admissions AS (
  SELECT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE a.subject_id IN (SELECT subject_id FROM eligible_patients)
    AND di.icd_code LIKE 'N17.%'  -- AKI ICD-10 codes
),

-- First ICU stay per admission
first_icu_stays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    TIMESTAMP_DIFF(s.outtime, s.intime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN aki_admissions a
    ON s.subject_id = a.subject_id AND s.hadm_id = a.hadm_id
  WHERE s.outtime IS NOT NULL  -- Exclude ongoing ICU stays
  QUALIFY ROW_NUMBER() OVER (PARTITION BY s.subject_id, s.hadm_id ORDER BY s.intime) = 1  -- First ICU stay
)

-- Calculate 25th percentile of LOS
SELECT
  PERCENTILE_CONT(los_days, 0.25) OVER() AS percentile_25_los_days
FROM first_icu_stays
LIMIT 1;