WITH
  -- Step 1: Identify injectable GLP-1 prescriptions
  glp1_prescriptions AS (
    SELECT
      hadm_id,
      starttime,
      stoptime
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
    WHERE
      (
        LOWER(drug) LIKE '%exenatide%'
        OR LOWER(drug) LIKE '%liraglutide%'
        OR LOWER(drug) LIKE '%dulaglutide%'
        OR LOWER(drug) LIKE '%semaglutide%'
        OR LOWER(drug) LIKE '%lixisenatide%'
        OR LOWER(drug) LIKE '%tirzepatide%'
      )
      AND LOWER(route) = 'sc' -- SC = Subcutaneous, the standard injectable route
  ),
  -- Step 2: Define the patient cohort
  cohort AS (
    SELECT
      adm.hadm_id,
      adm.admittime,
      adm.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      ON adm.subject_id = pat.subject_id
    WHERE
      pat.gender = 'F'
      -- Calculate age at admission and filter
      AND (
        pat.anchor_age + EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year
      ) BETWEEN 59 AND 69
      -- Filter for hospital stays >= 48 hours
      AND DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) >= 48
  ),
  -- Step 3: Flag GLP-1 use within the specified time windows for each admission
  cohort_drug_use AS (
    SELECT
      co.hadm_id,
      -- Flag for use in the first 48 hours: prescription started within the window
      MAX(
        CASE
          WHEN glp1.starttime BETWEEN co.admittime AND DATETIME_ADD(co.admittime, INTERVAL 48 HOUR)
            THEN 1
          ELSE 0
        END
      ) AS used_in_first_48h,
      -- Flag for use in the final 12 hours: prescription active period overlaps with the window
      MAX(
        CASE
          WHEN
            glp1.starttime < co.dischtime
            AND glp1.stoptime > DATETIME_SUB(co.dischtime, INTERVAL 12 HOUR)
            THEN 1
          ELSE 0
        END
      ) AS used_in_final_12h
    FROM cohort AS co
    LEFT JOIN glp1_prescriptions AS glp1
      ON co.hadm_id = glp1.hadm_id
    GROUP BY
      co.hadm_id
  )
-- Step 4: Calculate final prevalence statistics
SELECT
  COUNT(hadm_id) AS total_patients_in_cohort,
  SUM(used_in_first_48h) AS patients_on_glp1_first_48h,
  SUM(used_in_final_12h) AS patients_on_glp1_final_12h,
  -- Prevalence in first 48h (%)
  SAFE_DIVIDE(SUM(used_in_first_48h), COUNT(hadm_id)) * 100 AS prevalence_first_48h_percent,
  -- Prevalence in final 12h (%)
  SAFE_DIVIDE(SUM(used_in_final_12h), COUNT(hadm_id)) * 100 AS prevalence_final_12h_percent,
  -- Absolute percentage point (pp) difference
  ABS(
    (SAFE_DIVIDE(SUM(used_in_first_48h), COUNT(hadm_id)) * 100) - (SAFE_DIVIDE(SUM(used_in_final_12h), COUNT(hadm_id)) * 100)
  ) AS absolute_pp_difference
FROM cohort_drug_use;