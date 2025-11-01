WITH
hhs_cohort_admissions AS (
  -- Step 1: Identify hospital admissions for male patients aged 58-68 with an HHS diagnosis.
  SELECT DISTINCT
    p.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 58 AND 68
    -- Filter for Hyperosmolar Hyperglycemic State (HHS) using both ICD-9 and ICD-10 codes
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '2502%') -- Diabetes with hyperosmolarity
      OR (
        d.icd_version = 10 AND (
          d.icd_code LIKE 'E100%' OR -- T1DM with hyperosmolarity
          d.icd_code LIKE 'E110%' OR -- T2DM with hyperosmolarity
          d.icd_code LIKE 'E130%' OR -- Other specified DM with hyperosmolarity
          d.icd_code LIKE 'E140%'    -- Unspecified DM with hyperosmolarity
        )
      )
    )
),

radiology_counts AS (
  -- Step 2: Count the number of radiology procedures (CPT codes 70000-79999) for each admission.
  SELECT
    hadm_id,
    COUNT(*) AS num_radiology_procedures
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents`
  WHERE
    hcpcs_cd BETWEEN '70000' AND '79999' -- Standard CPT range for radiology procedures
  GROUP BY
    hadm_id
),

admissions_details AS (
  -- Step 3: Combine cohort, admission times, and procedure counts. Calculate LOS.
  SELECT
    hca.subject_id,
    hca.hadm_id,
    -- Calculate LOS in days, rounding up to the nearest day.
    CEIL(DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0) AS los_days,
    -- Use COALESCE to count 0 for admissions with no radiology procedures.
    COALESCE(rc.num_radiology_procedures, 0) AS num_radiology_procedures
  FROM
    hhs_cohort_admissions AS hca
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON hca.hadm_id = adm.hadm_id
  LEFT JOIN
    radiology_counts AS rc
    ON hca.hadm_id = rc.hadm_id
)

-- Final Step: Group by LOS category and calculate the requested metrics.
SELECT
  los_group,
  COUNT(DISTINCT subject_id) AS patient_count,
  COUNT(DISTINCT hadm_id) AS admission_count,
  AVG(num_radiology_procedures) AS mean_procedures_per_admission
FROM (
  SELECT
    *,
    CASE
      WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN los_days BETWEEN 5 AND 7 THEN '5-7 days'
      ELSE NULL
    END AS los_group
  FROM
    admissions_details
)
WHERE
  los_group IS NOT NULL
GROUP BY
  los_group
ORDER BY
  los_group;