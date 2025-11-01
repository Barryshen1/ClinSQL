WITH HemorrhagicStrokeAdmissions AS (
  -- First, find all hospital admissions (hadm_id) with a primary diagnosis of hemorrhagic stroke.
  SELECT
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    -- "Primary" diagnosis is indicated by seq_num = 1
    seq_num = 1
    -- Filter for relevant ICD-9 and ICD-10 codes for hemorrhagic stroke
    AND (
      (icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('430', '431', '432'))
      OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('I60', 'I61', 'I62'))
    )
)
-- Now, calculate the standard deviation of length of stay for the target cohort.
SELECT
  STDDEV(DATETIME_DIFF(adm.dischtime, adm.admittime, DAY)) AS sd_los_days
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
-- Join with patients to filter by age and gender
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  ON adm.subject_id = pat.subject_id
-- Join with our pre-filtered admissions to only include those with the correct diagnosis
INNER JOIN
  HemorrhagicStrokeAdmissions AS hsa
  ON adm.hadm_id = hsa.hadm_id
WHERE
  -- Filter for males aged 51 to 61
  pat.gender = 'M'
  AND pat.anchor_age BETWEEN 51 AND 61;