WITH
  -- Step 1: Define the cohort of female inpatients, aged 50-60, with both
  -- diabetes and heart failure, and a hospital stay of at least 72 hours.
  patient_cohort AS (
    SELECT
      adm.hadm_id,
      adm.admittime,
      adm.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      ON adm.hadm_id = dx.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
      ON dx.icd_code = d.icd_code AND dx.icd_version = d.icd_version
    WHERE
      pat.gender = 'F'
      AND (
        pat.anchor_age + EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year
      ) BETWEEN 50 AND 60
      AND DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) >= 72
    GROUP BY
      adm.hadm_id,
      adm.admittime,
      adm.dischtime
    HAVING
      -- Ensure at least one diagnosis for each condition exists for the admission
      COUNT(CASE WHEN LOWER(d.long_title) LIKE '%diabetes%' THEN 1 END) > 0
      AND COUNT(CASE WHEN LOWER(d.long_title) LIKE '%heart failure%' THEN 1 END) > 0
  ),

  -- Step 2: Identify the first initiation time of an injectable GLP-1 for each admission.
  glp1_initiations AS (
    SELECT
      hadm_id,
      MIN(starttime) AS first_glp1_time
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
    WHERE
      -- Filter for common injectable GLP-1 medications (generic and brand names)
      (
        LOWER(drug) LIKE '%semaglutide%' OR LOWER(drug) LIKE '%ozempic%'
        OR LOWER(drug) LIKE '%dulaglutide%' OR LOWER(drug) LIKE '%trulicity%'
        OR LOWER(drug) LIKE '%liraglutide%' OR LOWER(drug) LIKE '%victoza%'
        OR LOWER(drug) LIKE '%exenatide%' OR LOWER(drug) LIKE '%byetta%' OR LOWER(drug) LIKE '%bydureon%'
        OR LOWER(drug) LIKE '%lixisenatide%' OR LOWER(drug) LIKE '%adlyxin%'
      )
      -- Filter for subcutaneous route, the standard for these injectables
      AND LOWER(route) = 'sc'
    GROUP BY
      hadm_id
  ),

  -- Step 3: Join cohort with initiations and flag if initiation occurred in the target windows.
  analysis_data AS (
    SELECT
      cohort.hadm_id,
      -- Flag 1 if initiation was in the first 72 hours, else 0
      CASE
        WHEN
          glp1.first_glp1_time
          BETWEEN cohort.admittime AND DATETIME_ADD(cohort.admittime, INTERVAL 72 HOUR)
          THEN 1
        ELSE 0
      END AS initiated_in_first_72h,
      -- Flag 1 if initiation was in the final 72 hours, else 0
      CASE
        WHEN
          glp1.first_glp1_time
          BETWEEN DATETIME_SUB(cohort.dischtime, INTERVAL 72 HOUR) AND cohort.dischtime
          THEN 1
        ELSE 0
      END AS initiated_in_final_72h
    FROM patient_cohort AS cohort
    LEFT JOIN glp1_initiations AS glp1
      ON cohort.hadm_id = glp1.hadm_id
  )

-- Step 4: Aggregate the results and calculate the final metrics.
SELECT
  COUNT(hadm_id) AS total_eligible_admissions,
  SUM(initiated_in_first_72h) AS initiations_first_72h,
  SUM(initiated_in_final_72h) AS initiations_final_72h,
  ROUND(
    100.0 * SUM(initiated_in_first_72h) / COUNT(hadm_id),
    2
  ) AS rate_first_72h_percent,
  ROUND(
    100.0 * SUM(initiated_in_final_72h) / COUNT(hadm_id),
    2
  ) AS rate_final_72h_percent,
  -- Absolute change is the difference in percentage points (p.p.)
  ROUND(
    (100.0 * SUM(initiated_in_final_72h) / COUNT(hadm_id))
    - (100.0 * SUM(initiated_in_first_72h) / COUNT(hadm_id)),
    2
  ) AS absolute_change_pp,
  -- Relative change is the change as a percentage of the initial rate
  ROUND(
    100.0 * SAFE_DIVIDE(
      (SUM(initiated_in_final_72h) - SUM(initiated_in_first_72h)),
      SUM(initiated_in_first_72h)
    ),
    2
  ) AS relative_change_percent
FROM analysis_data;