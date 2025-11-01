WITH patient_selection AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 67 AND 77
),
pneumonia_admissions AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN patient_selection ps ON a.subject_id = ps.subject_id
  WHERE a.admission_type = 'EMERGENCY'
),
diagnosis_ranking AS (
  SELECT pa.hadm_id, pa.admittime, pa.dischtime, d.icd_code, d.icd_version, di.long_title,
         ROW_NUMBER() OVER (PARTITION BY pa.hadm_id ORDER BY d.seq_num) as diagnosis_rank
  FROM pneumonia_admissions pa
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON pa.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
),
primary_pneumonia_admissions AS (
  SELECT hadm_id, admittime, dischtime
  FROM diagnosis_ranking
  WHERE diagnosis_rank = 1 AND LOWER(long_title) LIKE '%pneumonia%' AND (LOWER(long_title) LIKE '%community%' OR LOWER(long_title) LIKE '%cap%')
)
SELECT APPROX_QUANTILES(DATE_DIFF(dischtime, admittime, DAY), 100)[OFFSET(25)] AS percentile_25th_los
FROM primary_pneumonia_admissions;