WITH cohort_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.subject_id = d.subject_id
      AND a.hadm_id     = d.hadm_id
      AND d.seq_num     = 1
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code    = dd.icd_code
      AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 36 AND 46
    AND a.insurance = 'Medicare'
    AND UPPER(a.admission_location) LIKE '%TRANSFER%'
    AND UPPER(a.admission_location) LIKE '%HOSPITAL%'
    AND LOWER(dd.long_title) LIKE '%hemorrhag%stroke%'
)

SELECT
  COUNT(*) AS index_admissions
FROM (
  SELECT
    subject_id,
    MIN(admittime) AS first_admission_time
  FROM
    cohort_admissions
  GROUP BY
    subject_id
);