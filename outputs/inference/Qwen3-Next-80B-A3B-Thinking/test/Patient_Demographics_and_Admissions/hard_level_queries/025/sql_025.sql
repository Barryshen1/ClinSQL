WITH first_admissions AS (
  SELECT
    subject_id,
    MIN(admittime) AS first_admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions`
  GROUP BY
    subject_id
)
SELECT
  COUNT(*) AS count
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN
  first_admissions fa
  ON a.subject_id = fa.subject_id
  AND a.admittime = fa.first_admittime
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON a.hadm_id = d.hadm_id
  AND d.seq_num = 1
JOIN
  `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
  ON d.icd_code = di.icd_code
  AND d.icd_version = di.icd_version
WHERE
  p.gender = 'F'
  AND a.insurance = 'Medicare'
  AND a.admission_location LIKE '%transfer%'
  AND a.admission_location LIKE '%hospital%'
  AND p.anchor_age BETWEEN 65 AND 75
  AND di.long_title LIKE '%heart failure%';