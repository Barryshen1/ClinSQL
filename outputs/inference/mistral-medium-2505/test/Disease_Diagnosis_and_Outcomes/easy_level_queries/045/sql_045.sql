WITH
-- Get female patients aged 77-87
female_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 77 AND 87
),

-- Get admissions with HF and COPD diagnoses
hf_copd_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    female_patients fp ON a.subject_id = fp.subject_id
  WHERE
    -- Ensure valid admission/discharge times
    a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.hadm_id IN (
      -- Subquery to find admissions with both HF and COPD
      SELECT
        hadm_id
      FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE
        -- HF: ICD-9 428.* or ICD-10 I50.*
        (diag.icd_code LIKE '428.%' OR diag.icd_code LIKE 'I50.%')
        -- COPD: ICD-9 496.* or ICD-10 J44.*
        AND diag.hadm_id IN (
          SELECT
            hadm_id
          FROM
            `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
          WHERE
            icd_code LIKE '496.%' OR icd_code LIKE 'J44.%'
        )
    )
)

-- Calculate standard deviation of LOS
SELECT
  STDDEV(los_days) AS sd_hospital_los_days
FROM
  hf_copd_admissions;