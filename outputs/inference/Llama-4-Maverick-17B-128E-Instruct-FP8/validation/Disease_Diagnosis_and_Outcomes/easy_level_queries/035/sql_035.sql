WITH eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE anchor_age = 70 AND gender = 'M'
),
admissions_for_patients AS (
  SELECT a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN eligible_patients p ON a.subject_id = p.subject_id
),
upper_gi_bleeding_admissions AS (
  SELECT a.hadm_id, a.admittime, a.dischtime
  FROM admissions_for_patients a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
  WHERE di.seq_num = 1 AND di.icd_code IN ('K92.0', 'K92.1', 'K92.2')
),
hospital_los AS (
  SELECT DATETIME_DIFF(dischtime, admittime, HOUR) / 24 AS los_days
  FROM upper_gi_bleeding_admissions
)
SELECT APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS percentile_75th_los
FROM hospital_los;