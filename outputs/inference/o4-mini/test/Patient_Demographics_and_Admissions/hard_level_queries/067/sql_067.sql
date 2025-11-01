WITH cohort_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_icd
      ON a.subject_id = d_icd.subject_id
      AND a.hadm_id = d_icd.hadm_id
      AND d_icd.seq_num = 1
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
      ON d_icd.icd_code = d.icd_code
      AND d_icd.icd_version = d.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 43 AND 53
    AND a.admission_location = 'EMERGENCY'
    AND a.insurance = 'Medicare'
    AND a.hospital_expire_flag = 0
    AND a.dischtime IS NOT NULL
    AND a.dischtime > a.admittime
    AND LOWER(d.long_title) LIKE '%bowel obstruction%'
)

SELECT
  COUNT(1) AS index_admission_count
FROM
  cohort_admissions
WHERE
  rn = 1;