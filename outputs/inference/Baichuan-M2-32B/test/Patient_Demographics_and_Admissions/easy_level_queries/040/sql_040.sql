WITH stroke_patients AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 35 AND 45
    AND d.icd_code LIKE 'I6%'
    AND d.icd_version = 10  -- ICD-10
),
icu_stays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    TIMESTAMP_DIFF(s.outtime, s.intime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  WHERE s.hadm_id IN (SELECT hadm_id FROM stroke_patients)
)
SELECT
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_days
FROM icu_stays;