WITH pancreatitis_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 72 AND 82
    AND a.insurance = 'Medicare'
    AND (
      LOWER(a.admission_location) LIKE '%emergency%'
      OR LOWER(a.admission_location) LIKE '%ed%'
    )
    AND d.seq_num = 1
    AND (
      (d.icd_version = 9 AND d.icd_code = '5770')
      OR (d.icd_version = 10 AND d.icd_code LIKE 'K85%')
    )
    AND a.hospital_expire_flag = 0
)
SELECT
  COUNT(*) AS total_index_admissions
FROM (
  SELECT
    subject_id,
    MIN(admittime) AS index_admittime
  FROM
    pancreatitis_admissions
  GROUP BY
    subject_id
);