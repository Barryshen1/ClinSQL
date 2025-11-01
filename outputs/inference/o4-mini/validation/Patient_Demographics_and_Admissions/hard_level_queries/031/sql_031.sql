WITH cohort AS (
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
      AND a.hadm_id    = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 62 AND 72
    AND a.insurance = 'Medicare'
    AND LOWER(a.admission_location) LIKE '%emergency%'
    AND d.seq_num = 1
    AND (
      (d.icd_version = 9  AND d.icd_code = '780.2')
      OR
      (d.icd_version = 10 AND d.icd_code = 'R55')
    )
),
index_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    ROW_NUMBER() OVER(PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM
    cohort
)
SELECT
  COUNT(*) AS total_index_admissions
FROM
  index_admissions
WHERE
  rn = 1;