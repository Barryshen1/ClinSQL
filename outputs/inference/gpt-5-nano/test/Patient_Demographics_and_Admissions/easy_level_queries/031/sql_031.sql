WITH
  -- HF-related admissions for eligible females aged 38-48
  hf_admissions AS (
    SELECT
      a.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      ON di.subject_id = a.subject_id
     AND di.hadm_id = a.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
      ON di.icd_code = dd.icd_code
     AND di.icd_version = dd.icd_version
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON p.subject_id = a.subject_id
    WHERE p.gender = 'F'
      AND p.anchor_age BETWEEN 38 AND 48
      AND LOWER(dd.long_title) LIKE '%heart failure%'
  ),
  -- First HF admission per patient (earliest admittime)
  first_hf AS (
    SELECT
      subject_id,
      hadm_id,
      admittime,
      dischtime,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
    FROM hf_admissions
  ),
  first_hf_per_patient AS (
    SELECT
      subject_id,
      hadm_id,
      admittime,
      dischtime
    FROM first_hf
    WHERE rn = 1
  ),
  -- Patients with a 30-day readmission after their first HF admission
  readmission_flag AS (
    SELECT DISTINCT f.subject_id
    FROM first_hf_per_patient AS f
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a2
      ON a2.subject_id = f.subject_id
     AND a2.admittime > f.dischtime
     AND a2.admittime <= TIMESTAMP_ADD(f.dischtime, INTERVAL 30 DAY)
  )
SELECT
  -- Total number of patients with a first HF admission in the cohort
  (SELECT COUNT(*) FROM first_hf_per_patient) AS total_first_hf_patients,
  -- Total number of those patients who were readmitted within 30 days
  (SELECT COUNT(*) FROM readmission_flag) AS total_readmitted_within_30d,
  -- Readmission rate: readmitted / total
  SAFE_DIVIDE(
    (SELECT COUNT(*) FROM readmission_flag),
    (SELECT COUNT(*) FROM first_hf_per_patient)
  ) AS readmission_rate_30day
;