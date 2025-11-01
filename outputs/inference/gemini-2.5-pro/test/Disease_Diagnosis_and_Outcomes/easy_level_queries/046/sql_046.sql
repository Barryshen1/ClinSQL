WITH HemorrhagicStrokeAdmissions AS (
  -- First, identify all hospital admissions with a primary diagnosis of hemorrhagic stroke
  SELECT DISTINCT
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    -- 'seq_num = 1' is used to identify the primary diagnosis
    seq_num = 1
    AND (
      -- ICD-9 codes for hemorrhagic stroke
      (icd_version = 9 AND (icd_code = '430' OR icd_code = '431' OR icd_code LIKE '432%'))
      -- ICD-10 codes for hemorrhagic stroke
      OR (icd_version = 10 AND (icd_code LIKE 'I60%' OR icd_code LIKE 'I61%' OR icd_code LIKE 'I62%'))
    )
)
-- Now, calculate the standard deviation of LOS for the target patient cohort
SELECT
  STDDEV(DATETIME_DIFF(adm.dischtime, adm.admittime, DAY)) AS sd_hospital_los_days
FROM
  `physionet-data.mimiciv_3_1_hosp.patients` AS pat
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  ON pat.subject_id = adm.subject_id
INNER JOIN
  HemorrhagicStrokeAdmissions AS hs
  ON adm.hadm_id = hs.hadm_id
WHERE
  -- Filter for males aged 43-53
  pat.gender = 'M'
  AND pat.anchor_age BETWEEN 43 AND 53;