WITH first_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    admission_location,
    insurance,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions`
)
SELECT
  COUNT(*) AS num_admissions
FROM
  first_admissions fa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON fa.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON fa.hadm_id = d.hadm_id
    AND d.seq_num = 1
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
WHERE
  fa.rn = 1                                 -- index (first) admission per patient
  AND p.gender = 'M'                        -- male
  AND p.anchor_age BETWEEN 43 AND 53        -- age 43–53
  AND LOWER(fa.admission_location) LIKE '%emergency%'  -- admitted from ED
  AND LOWER(fa.insurance) = 'medicare'      -- Medicare insurance
  AND LOWER(dd.long_title) LIKE '%diabetic ketoacidosis%'  -- principal diagnosis DKA
;