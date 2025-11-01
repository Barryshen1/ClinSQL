WITH index_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    admission_type,
    insurance,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions`
)
SELECT
  COUNT(DISTINCT ia.hadm_id) AS total_index_cohort_admissions
FROM
  index_admissions ia
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ia.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON ia.hadm_id = di.hadm_id
      AND di.seq_num = 1
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
      AND di.icd_version = dd.icd_version
WHERE
  ia.rn = 1
  AND p.gender = 'F'
  AND p.anchor_age BETWEEN 72 AND 82
  AND ia.insurance = 'Medicare'
  AND ia.admission_type = 'EMERGENCY'
  AND LOWER(dd.long_title) LIKE '%acute pancreatitis%';