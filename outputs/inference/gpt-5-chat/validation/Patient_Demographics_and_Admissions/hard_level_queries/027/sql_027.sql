WITH cohort AS (
  SELECT
    p.subject_id,
    adm.hadm_id,
    adm.admittime,
    p.gender,
    p.anchor_age,
    adm.insurance,
    adm.admission_location,
    diag.icd_code,
    diag.icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON p.subject_id = adm.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
    AND LOWER(adm.insurance) = 'medicare'
    AND LOWER(adm.admission_location) LIKE 'emergency%'
    AND diag.seq_num = 1
    AND (
      (diag.icd_version = 9 AND diag.icd_code IN ('5770','5771','5772'))
      OR (diag.icd_version = 10 AND diag.icd_code LIKE 'K85%')
    )
),
index_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM cohort
)
SELECT
  COUNT(*) AS num_index_admissions
FROM index_admissions
WHERE rn = 1;