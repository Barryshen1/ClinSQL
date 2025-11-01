WITH cohort_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      ON a.subject_id = di.subject_id
      AND a.hadm_id = di.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON di.icd_code = dd.icd_code
      AND di.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 72 AND 82
    AND a.admission_type = 'EMERGENCY'
    AND a.insurance = 'Medicare'
    AND a.hospital_expire_flag = 0
    AND di.seq_num = 1
    AND UPPER(COALESCE(dd.long_title, '')) LIKE '%ACUTE PANCREATITIS%'
),
index_per_patient AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM
    cohort_admissions
)
SELECT
  COUNT(*) AS n_index_admissions
FROM
  index_per_patient
WHERE
  rn = 1;