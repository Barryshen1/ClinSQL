WITH female_medicare_patients AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.insurance,
    a.admission_location,
    a.discharge_location,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'EMERGENCY DEPARTMENT'
    AND a.discharge_location IS NOT NULL
    AND a.hospital_expire_flag = 0
),

admissions_with_age AS (
  SELECT
    fmp.*,
    EXTRACT(YEAR FROM fmp.admittime) - fmp.anchor_year + fmp.anchor_age AS age_at_admission
  FROM
    female_medicare_patients fmp
  WHERE
    EXTRACT(YEAR FROM fmp.admittime) - fmp.anchor_year + fmp.anchor_age BETWEEN 82 AND 92
),

pancreatitis_admissions AS (
  SELECT
    a.hadm_id
  FROM
    admissions_with_age a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  ON
    a.hadm_id = diag.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
  ON
    diag.icd_code = d.icd_code
    AND diag.icd_version = d.icd_version
  WHERE
    diag.seq_num = 1  -- Principal diagnosis
    AND (
      (diag.icd_version = 9 AND diag.icd_code = '577.0')  -- ICD-9 code for acute pancreatitis
      OR
      (diag.icd_version = 10 AND diag.icd_code LIKE 'K85%')  -- ICD-10 codes for acute pancreatitis
    )
)

SELECT
  COUNT(DISTINCT hadm_id) AS num_admissions
FROM
  pancreatitis_admissions;