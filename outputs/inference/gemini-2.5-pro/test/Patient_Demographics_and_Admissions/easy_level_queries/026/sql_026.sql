WITH cabg_hadm_ids AS (
  -- Find all hospital admissions (hadm_id) where a CABG procedure was performed
  SELECT DISTINCT
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  WHERE
    -- ICD-9 codes for CABG
    (icd_version = 9 AND SUBSTR(icd_code, 1, 4) BETWEEN '3610' AND '3619')
    OR
    -- ICD-10-PCS codes for CABG (Bypass of Coronary Arteries)
    (icd_version = 10 AND SUBSTR(icd_code, 1, 3) = '021')
),

first_admissions AS (
  -- Identify the first hospital admission for each patient
  SELECT
    subject_id,
    hadm_id,
    hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS admission_rank
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions`
)

-- Final cohort selection and calculation
SELECT
  -- The question asks for the "25th percentile of mortality". As this is a binary outcome (0 or 1),
  -- the most meaningful statistic is the mortality rate, calculated as the average of the outcome flag.
  AVG(fadm.hospital_expire_flag) AS mortality_rate
FROM
  first_admissions AS fadm
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  ON fadm.subject_id = pat.subject_id
INNER JOIN
  cabg_hadm_ids AS cabg
  ON fadm.hadm_id = cabg.hadm_id
WHERE
  fadm.admission_rank = 1 -- Filter for the first admission only
  AND pat.gender = 'M' -- Filter for male patients
  AND pat.anchor_age BETWEEN 48 AND 58; -- Filter for the specified age range;