WITH patient_cohort AS (
  SELECT p.subject_id, p.anchor_age, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 43 AND 53
),
stroke_admissions AS (
  SELECT pc.subject_id, pc.hadm_id, pc.admittime, pc.dischtime, di.long_title, di.icd_code, di.icd_version,
         ROW_NUMBER() OVER (PARTITION BY pc.hadm_id ORDER BY d.seq_num) AS diagnosis_priority
  FROM patient_cohort pc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON pc.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE di.icd_version = 10  -- Assuming ICD-10 is used; adjust if necessary
  AND di.long_title LIKE '%Hemorrhagic stroke%'  -- This might need refinement based on actual ICD codes used
),
primary_stroke_admissions AS (
  SELECT hadm_id, admittime, dischtime
  FROM stroke_admissions
  WHERE diagnosis_priority = 1
)
SELECT STDDEV(DATE_DIFF(dischtime, admittime, DAY)) AS sd_hospital_los
FROM primary_stroke_admissions;