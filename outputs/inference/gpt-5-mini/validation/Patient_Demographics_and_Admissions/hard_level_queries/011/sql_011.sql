WITH qualifying_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    USING (subject_id)
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
    AND LOWER(IFNULL(a.insurance, '')) LIKE '%medicare%'
    AND LOWER(IFNULL(a.admission_location, '')) LIKE '%emerg%'
    AND a.dischtime IS NOT NULL
    AND d.seq_num = 1
    AND (
      (d.icd_version = 9 AND LEFT(d.icd_code, 3) IN ('430', '431', '432'))
      OR
      (d.icd_version = 10 AND LEFT(UPPER(d.icd_code), 3) IN ('I60', 'I61', 'I62'))
    )
),
index_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM qualifying_admissions
)
SELECT
  COUNT(*) AS index_admissions_count
FROM
  index_admissions
WHERE
  rn = 1;