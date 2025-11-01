WITH
  -- Step 1: Define the base patient cohort (males, aged 48-58)
  patient_base AS (
    SELECT
      subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE
      gender = 'M'
      AND anchor_age BETWEEN 48 AND 58
  ),
  -- Step 2: Identify admissions with a sepsis diagnosis
  sepsis_admissions AS (
    SELECT DISTINCT
      hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
      icd_code IN (
        SELECT
          icd_code
        FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
        WHERE
          LOWER(long_title) LIKE '%sepsis%'
      )
  ),
  -- Step 3: Identify admissions with a septic shock diagnosis (for exclusion)
  shock_admissions AS (
    SELECT DISTINCT
      hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
      icd_code IN (
        SELECT
          icd_code
        FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
        WHERE
          LOWER(long_title) LIKE '%septic shock%'
      )
  ),
  -- Step 4: Count ultrasound procedures per admission
  ultrasound_counts AS (
    SELECT
      p.hadm_id,
      COUNT(p.icd_code) AS ultrasound_count
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS p
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS d
      ON p.icd_code = d.icd_code
      AND p.icd_version = d.icd_version
    WHERE
      LOWER(d.long_title) LIKE '%ultrasound%' OR LOWER(d.long_title) LIKE '%echocardiogram%'
    GROUP BY
      p.hadm_id
  ),
  -- Step 5: Identify all admissions that include an ICU stay
  icu_admissions AS (
    SELECT DISTINCT
      hadm_id
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ),
  -- Step 6: Assemble the final cohort by combining the above criteria
  final_cohort AS (
    SELECT
      adm.subject_id,
      adm.hadm_id,
      CASE
        WHEN DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 4
          THEN '1-4 days'
        ELSE '5-8 days'
      END AS los_group,
      CASE
        WHEN icu.hadm_id IS NOT NULL
          THEN 'ICU'
        ELSE 'No ICU'
      END AS icu_status,
      COALESCE(uc.ultrasound_count, 0) AS num_ultrasounds
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    -- Join to get ultrasound counts
    LEFT JOIN
      ultrasound_counts AS uc
      ON adm.hadm_id = uc.hadm_id
    -- Join to check for an ICU stay
    LEFT JOIN
      icu_admissions AS icu
      ON adm.hadm_id = icu.hadm_id
    -- Filter the admissions based on the defined criteria
    WHERE
      adm.subject_id IN (
        SELECT subject_id FROM patient_base
      )
      AND adm.hadm_id IN (
        SELECT hadm_id FROM sepsis_admissions
      )
      AND adm.hadm_id NOT IN (
        SELECT hadm_id FROM shock_admissions
      )
      AND DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 8
  )
-- Step 7: Aggregate the results to get the final output
SELECT
  icu_status,
  los_group,
  COUNT(DISTINCT subject_id) AS patient_count,
  AVG(num_ultrasounds) AS mean_ultrasounds_per_admission
FROM final_cohort
GROUP BY
  icu_status,
  los_group
ORDER BY
  icu_status DESC,
  los_group;