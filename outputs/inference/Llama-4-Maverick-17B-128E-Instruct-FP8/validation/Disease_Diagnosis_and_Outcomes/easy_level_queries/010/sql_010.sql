WITH patient_cohort AS (
  SELECT p.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 49 AND 59
  AND a.hadm_id IN (
    SELECT hadm_id
    FROM `physionet-data.mimimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_version = 10 AND icd_code IN ('J440', 'J441')
    AND seq_num = 1  
  )
),
hospital_los AS (
  SELECT hadm_id, DATETIME_DIFF(dischtime, admittime, HOUR) / 24 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  WHERE hadm_id IN (SELECT hadm_id FROM patient_cohort)
)
SELECT APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS percentile_25th_los
FROM hospital_los;