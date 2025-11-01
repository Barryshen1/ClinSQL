WITH base AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS LOS_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'Male'
    AND p.anchor_age >= 75
    AND p.anchor_age <= 85
    AND a.dischtime IS NOT NULL
),
cohort AS (
  SELECT
    b.subject_id,
    b.hadm_id,
    b.LOS_days
  FROM base AS b
  WHERE b.LOS_days >= 0
    -- Must have an ischemic heart disease / acute coronary syndrome diagnosis
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dicd
        ON di.icd_code = dicd.icd_code
       AND di.icd_version = dicd.icd_version
      WHERE di.subject_id = b.subject_id
        AND di.hadm_id = b.hadm_id
        AND (
          LOWER(dicd.long_title) LIKE '%ischemi%'
          OR LOWER(dicd.long_title) LIKE '%coronary%'
          OR LOWER(dicd.long_title) LIKE '%myocardial%'
          OR LOWER(dicd.long_title) LIKE '%infarction%'
          OR LOWER(dicd.long_title) LIKE '%acute coronary syndrome%'
          OR LOWER(dicd.long_title) LIKE '%ischemic heart disease%'
        )
    )
    -- Must also have a COPD diagnosis
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dicd
        ON di.icd_code = dicd.icd_code
       AND di.icd_version = dicd.icd_version
      WHERE di.subject_id = b.subject_id
        AND di.hadm_id = b.hadm_id
        AND (
          LOWER(dicd.long_title) LIKE '%copd%'
          OR LOWER(dicd.long_title) LIKE '%emphysema%'
          OR LOWER(dicd.long_title) LIKE '%chronic bronchitis%'
        )
    )
)
SELECT
  quantiles[OFFSET(75)] AS p75_hospital_los_days
FROM (
  SELECT APPROX_QUANTILES(los_days, 100) AS quantiles
  FROM cohort
) AS q;