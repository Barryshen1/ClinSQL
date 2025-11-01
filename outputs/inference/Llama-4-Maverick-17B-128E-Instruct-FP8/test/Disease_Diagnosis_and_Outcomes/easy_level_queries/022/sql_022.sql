WITH patient_filter AS (
  SELECT p.subject_id, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 71 AND 81
),
stroke_patients AS (
  SELECT di.subject_id, di.hadm_id, 
         ROW_NUMBER() OVER (PARTITION BY di.subject_id, di.hadm_id ORDER BY di.seq_num) AS diagnosis_rank
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd 
    ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
  WHERE di.icd_version = 10 AND dicd.long_title LIKE '%Ischemic stroke%' 
    AND di.subject_id IN (SELECT subject_id FROM patient_filter)
),
primary_stroke_admissions AS (
  SELECT sp.hadm_id
  FROM stroke_patients sp
  WHERE sp.diagnosis_rank = 1
),
hospital_los AS (
  SELECT a.hadm_id, 
         DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  WHERE a.hadm_id IN (SELECT hadm_id FROM primary_stroke_admissions)
)
SELECT 
  APPROX_QUANTILES(los_days, 100)[
    OFFSET(25)] AS q1,
  APPROX_QUANTILES(los_days, 100)[
    OFFSET(75)] AS q3,
  APPROX_QUANTILES(los_days, 100)[
    OFFSET(75)] - APPROX_QUANTILES(los_days, 100)[
    OFFSET(25)] AS iqr
FROM hospital_los;