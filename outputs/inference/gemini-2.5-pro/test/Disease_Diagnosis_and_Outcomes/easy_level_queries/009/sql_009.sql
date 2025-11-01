WITH qualifying_hadms AS (
  -- Step 1: Find all hospital admissions (hadm_id) that have diagnoses for BOTH
  -- Ischemic Heart Disease/ACS AND COPD.
  SELECT
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  GROUP BY
    hadm_id
  HAVING
    -- Use MAX with CASE to check for the presence of at least one IHD/ACS diagnosis
    MAX(
      CASE
        WHEN
          LOWER(dd.long_title) LIKE '%acute myocardial infarction%'
          OR LOWER(dd.long_title) LIKE '%unstable angina%'
          OR LOWER(dd.long_title) LIKE '%ischemic cardiomyopathy%'
          OR LOWER(dd.long_title) LIKE '%coronary arteriosclerosis%' -- a common form of IHD
          OR LOWER(dd.long_title) LIKE '%acute coronary syndrome%'
          OR LOWER(dd.long_title) LIKE '%ischemic heart disease%'
          THEN 1
        ELSE 0
      END
    ) = 1
    AND
    -- And check for the presence of at least one COPD diagnosis
    MAX(
      CASE
        WHEN
          LOWER(dd.long_title) LIKE '%chronic obstructive pulmonary disease%'
          OR LOWER(dd.long_title) LIKE '%copd%'
          OR LOWER(dd.long_title) LIKE '%emphysema%'
          OR LOWER(dd.long_title) LIKE '%chronic bronchitis%'
          THEN 1
        ELSE 0
      END
    ) = 1
), cohort_los AS (
  -- Step 2: Join with admissions and patients to filter by demographics
  -- and calculate LOS for the qualifying admissions.
  SELECT
    -- Calculate LOS in fractional days for higher precision before aggregation
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  -- Ensure the admission has the required comorbidities by joining with the previous CTE
  INNER JOIN
    qualifying_hadms AS qh
    ON adm.hadm_id = qh.hadm_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 75 AND 85
    -- Sanity checks for a valid LOS calculation
    AND adm.dischtime IS NOT NULL
    AND adm.admittime IS NOT NULL
    AND adm.dischtime > adm.admittime
)
-- Step 3: Calculate the 75th percentile of the LOS for the final cohort
SELECT
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS los_days_75th_percentile
FROM
  cohort_los;