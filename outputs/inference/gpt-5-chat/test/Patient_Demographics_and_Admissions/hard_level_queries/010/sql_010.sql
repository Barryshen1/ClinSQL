WITH criteria_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id
    AND a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
    AND a.insurance = 'Medicare'
    AND LOWER(a.admission_location) LIKE 'emerg%'
    AND d.seq_num = 1
    AND LOWER(dd.long_title) LIKE '%diabetic ketoacidosis%'
)
, index_admissions AS (
  SELECT
    subject_id,
    MIN(admittime) AS first_admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions`
  GROUP BY subject_id
)
SELECT
  COUNT(DISTINCT c.hadm_id) AS num_admissions
FROM
  criteria_admissions c
JOIN
  index_admissions idx
  ON c.subject_id = idx.subject_id
  AND c.admittime = idx.first_admittime;