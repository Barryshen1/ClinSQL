WITH
  -- Step 1: Identify hospital admissions for Acute Coronary Syndrome (ACS)
  acs_admissions AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dx
      ON dx.icd_code = d_dx.icd_code AND dx.icd_version = d_dx.icd_version
    WHERE
      LOWER(d_dx.long_title) LIKE '%acute myocardial infarction%'
      OR LOWER(d_dx.long_title) LIKE '%unstable angina%'
      OR LOWER(d_dx.long_title) LIKE '%acute coronary syndrome%'
  ),

  -- Step 2: Identify the specific patient cohort (males, 87-97, with ACS)
  patient_cohort AS (
    SELECT
      adm.subject_id,
      adm.hadm_id,
      adm.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      ON adm.subject_id = pat.subject_id
    INNER JOIN acs_admissions ON adm.hadm_id = acs_admissions.hadm_id
    WHERE
      pat.gender = 'M'
      AND (
        pat.anchor_age + DATETIME_DIFF(
          adm.admittime, DATETIME(pat.anchor_year, 1, 1, 0, 0, 0), YEAR
        )
      ) BETWEEN 87 AND 97
  ),

  -- Step 3: Find the first (index) Troponin T for each patient in the cohort
  index_troponin AS (
    SELECT
      le.hadm_id,
      le.valuenum,
      ROW_NUMBER() OVER (
        PARTITION BY le.hadm_id ORDER BY le.charttime ASC
      ) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    INNER JOIN patient_cohort AS cohort ON le.hadm_id = cohort.hadm_id
    WHERE
      le.itemid = 51003  -- Troponin T
      AND le.valuenum IS NOT NULL
  ),

  -- Step 4: Categorize the index Troponin T values and join with mortality data
  troponin_categorized AS (
    SELECT
      it.hadm_id,
      cohort.hospital_expire_flag,
      CASE
        WHEN it.valuenum <= 0.01
        THEN 'Normal/Minimal'
        WHEN it.valuenum > 0.01 AND it.valuenum <= 0.04
        THEN 'Borderline'
        WHEN it.valuenum > 0.04
        THEN 'Elevated'
        ELSE NULL
      END AS troponin_category
    FROM index_troponin AS it
    INNER JOIN
      patient_cohort AS cohort ON it.hadm_id = cohort.hadm_id
    WHERE
      it.rn = 1  -- Only the first measurement
  )

-- Step 5: Aggregate results to get counts, percentages, and mortality rates
SELECT
  troponin_category,
  COUNT(hadm_id) AS patient_count,
  ROUND(
    COUNT(hadm_id) * 100.0 / SUM(COUNT(hadm_id)) OVER (), 2
  ) AS percentage_of_patients,
  ROUND(
    SUM(hospital_expire_flag) * 100.0 / COUNT(hadm_id), 2
  ) AS in_hospital_mortality_rate
FROM troponin_categorized
WHERE troponin_category IS NOT NULL
GROUP BY
  troponin_category
ORDER BY
  CASE
    WHEN troponin_category = 'Normal/Minimal' THEN 1
    WHEN troponin_category = 'Borderline' THEN 2
    WHEN troponin_category = 'Elevated' THEN 3
  END;