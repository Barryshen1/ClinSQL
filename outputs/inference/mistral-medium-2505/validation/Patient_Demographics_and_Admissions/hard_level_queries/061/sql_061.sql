WITH female_medicare_transfers AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    p.anchor_age,
    p.gender,
    a.insurance,
    a.admission_type
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 63 AND 73
    AND a.insurance = 'Medicare'
    AND a.admission_type = 'TRANSFER'
)

SELECT
  COUNT(DISTINCT f.hadm_id) AS total_admissions
FROM
  female_medicare_transfers f
JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
ON
  f.hadm_id = d.hadm_id
WHERE
  d.seq_num = 1  -- Principal diagnosis
  AND (
    (d.icd_version = 10 AND d.icd_code LIKE 'I48.%')  -- ICD-10 code for atrial fibrillation
    OR
    (d.icd_version = 9 AND d.icd_code = '427.31')      -- ICD-9 code for atrial fibrillation
  )
;