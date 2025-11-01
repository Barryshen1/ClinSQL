WITH patient_cohort AS (
  SELECT p.subject_id, a.hadm_id, icu.stay_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON a.hadm_id = icu.hadm_id
  WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 59 AND 69
  AND a.admission_location = 'EMERGENCY ROOM'
),
max_sbp AS (
  SELECT pc.subject_id, pc.hadm_id, pc.stay_id, MAX(ce.valuenum) AS max_sbp
  FROM patient_cohort pc
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON pc.stay_id = ce.stay_id
  WHERE ce.itemid = 220050  
  GROUP BY pc.subject_id, pc.hadm_id, pc.stay_id
)
SELECT APPROX_QUANTILES(max_sbp.max_sbp, 100)[OFFSET(75)] AS percentile_75th
FROM max_sbp;