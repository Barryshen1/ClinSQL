WITH
  -- Step 1: Filter for the cohort of interest (female, 75-85, transfer from hospital)
  -- and categorize their discharge disposition.
  PatientCohort AS (
    SELECT
      adm.hadm_id,
      DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
      CASE
        WHEN adm.hospital_expire_flag = 1
        THEN 'In-hospital Death'
        WHEN adm.discharge_location IN ('HOME', 'HOME HEALTH CARE')
        THEN 'Home'
        WHEN adm.discharge_location = 'HOSPICE'
        THEN 'Hospice'
        ELSE NULL
      END AS discharge_category
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      ON adm.subject_id = pat.subject_id
    WHERE
      pat.gender = 'F'
      AND pat.anchor_age BETWEEN 75 AND 85
      AND adm.admission_location = 'TRANSFER FROM HOSPITAL'
  )
-- Step 2: Group by the discharge category and calculate the required metrics.
SELECT
  discharge_category,
  COUNT(hadm_id) AS total_admissions,
  -- Calculate the proportion of admissions with LOS >= 7 days
  SAFE_DIVIDE(
    COUNTIF(los_days >= 7),
    COUNT(hadm_id)
  ) * 100 AS proportion_los_ge_7_percent,
  -- Calculate the "7-day percentile", interpreted as the percentile rank of a 7-day stay.
  -- This is the percentage of stays with LOS < 7 days.
  SAFE_DIVIDE(
    COUNTIF(los_days < 7),
    COUNT(hadm_id)
  ) * 100 AS percentile_rank_of_7_days
FROM
  PatientCohort
WHERE
  -- Exclude admissions that do not fall into the specified discharge categories
  discharge_category IS NOT NULL
GROUP BY
  discharge_category
ORDER BY
  discharge_category;