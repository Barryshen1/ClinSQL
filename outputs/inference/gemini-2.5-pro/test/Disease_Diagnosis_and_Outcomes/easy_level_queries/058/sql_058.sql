WITH hemorrhagic_stroke_admissions AS (
  -- First, identify all hospital admissions with a primary diagnosis of hemorrhagic stroke
  SELECT
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    seq_num = 1
    AND (
      -- ICD-9 codes for hemorrhagic stroke
      (icd_version = 9 AND (
        icd_code LIKE '430%'
        OR icd_code LIKE '431%'
        OR icd_code LIKE '432%')
      )
      -- ICD-10 codes for hemorrhagic stroke
      OR (icd_version = 10 AND (
        icd_code LIKE 'I60%'
        OR icd_code LIKE 'I61%'
        OR icd_code LIKE 'I62%')
      )
    )
),
cohort_los AS (
  -- Next, filter for the specific patient cohort and calculate their hospital length of stay
  SELECT
    -- Calculate hospital length of stay in days
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS hospital_los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN
    hemorrhagic_stroke_admissions AS hsa
    ON adm.hadm_id = hsa.hadm_id
  WHERE
    -- Filter for females
    pat.gender = 'F'
    -- Filter for patients aged 37-47 at the time of admission
    AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age) BETWEEN 37 AND 47
)
-- Finally, calculate the 75th percentile of the hospital LOS for the cohort
SELECT
  APPROX_QUANTILES(hospital_los_days, 100)[OFFSET(75)] AS p75_hospital_los_days
FROM
  cohort_los;