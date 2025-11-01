WITH
-- CTE to identify the cohort of hospital admissions based on patient demographics,
-- length of stay, and diagnosis of ischemic stroke.
cohort AS (
  SELECT
    adm.hadm_id,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  WHERE
    -- Filter for women aged 40-50
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 40 AND 50
    -- Filter for hospital stays between 1 and 7 days
    AND DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 7
    -- Filter for admissions that have a relevant ischemic stroke diagnosis code
    AND adm.hadm_id IN (
      SELECT DISTINCT
        hadm_id
      FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE
        -- ICD-9 codes for occlusion of cerebral/precerebral arteries
        (icd_version = 9 AND (icd_code LIKE '433%' OR icd_code LIKE '434%'))
        -- ICD-10 code for cerebral infarction
        OR (icd_version = 10 AND icd_code LIKE 'I63%')
    )
),

-- CTE to count the number of imaging procedures per admission.
-- Imaging is defined by standard ICD-9 and ICD-10-PCS code ranges.
imaging_counts AS (
  SELECT
    hadm_id,
    COUNT(*) AS num_imaging_procedures
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  WHERE
    -- ICD-9 codes for Diagnostic Radiology (87) and other related procedures (88)
    (icd_version = 9 AND (icd_code LIKE '87%' OR icd_code LIKE '88%'))
    -- ICD-10-PCS codes for the Imaging section (B)
    OR (icd_version = 10 AND icd_code LIKE 'B%')
  GROUP BY
    hadm_id
),

-- CTE to create a distinct list of hospital admissions that included an ICU stay.
icu_admissions AS (
  SELECT DISTINCT
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays`
)

-- Final query to join the cohort with procedure counts and ICU status,
-- then stratify and aggregate the results.
SELECT
  CASE
    WHEN icu.hadm_id IS NOT NULL THEN 'ICU Stay'
    ELSE 'No ICU Stay'
  END AS icu_status,
  CASE
    WHEN cohort.los_days BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN cohort.los_days BETWEEN 5 AND 7 THEN '5-7 days'
  END AS length_of_stay_group,
  ROUND(AVG(COALESCE(img.num_imaging_procedures, 0)), 2) AS mean_imaging_procedures,
  MIN(COALESCE(img.num_imaging_procedures, 0)) AS min_imaging_procedures,
  MAX(COALESCE(img.num_imaging_procedures, 0)) AS max_imaging_procedures
FROM
  cohort
LEFT JOIN
  imaging_counts AS img
  ON cohort.hadm_id = img.hadm_id
LEFT JOIN
  icu_admissions AS icu
  ON cohort.hadm_id = icu.hadm_id
GROUP BY
  icu_status,
  length_of_stay_group
ORDER BY
  icu_status DESC,
  length_of_stay_group;