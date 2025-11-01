WITH patient_data AS (
  SELECT p.subject_id, p.anchor_age, ce.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON p.subject_id = ce.subject_id
  WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 59 AND 69
  AND ce.itemid = 220050  -- Systolic blood pressure
  AND ce.valuenum IS NOT NULL
)
SELECT APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS systolic_bp_75th_percentile
FROM patient_data;