WITH patients_filtered AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 52 AND 62
),
aki_diagnoses AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_version = 10 AND LOWER(long_title) LIKE '%acute kidney injury%'
),
admissions_with_aki AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime,
         ROW_NUMBER() OVER (PARTITION BY a.hadm_id ORDER BY d.seq_num) AS diagnosis_priority
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE a.subject_id IN (SELECT subject_id FROM patients_filtered)
    AND d.icd_code IN (SELECT icd_code FROM aki_diagnoses)
    AND d.icd_version = 10
),
primary_aki_admissions AS (
  SELECT subject_id, hadm_id, admittime, dischtime
  FROM admissions_with_aki
  WHERE diagnosis_priority = 1
)
SELECT 
  APPROX_QUANTILES(DATETIME_DIFF(dischtime, admittime, MINUTE), 100)[OFFSET(75)] AS los_75th_percentile
FROM primary_aki_admissions;