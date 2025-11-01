WITH
  base_cohort AS (
    -- Step 1: Identify male ICU patients aged 40-50
    SELECT
      i.subject_id,
      i.hadm_id,
      i.stay_id,
      i.intime,
      i.los
    FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON i.subject_id = p.subject_id
    WHERE
      p.gender = 'M' AND p.anchor_age BETWEEN 40 AND 50
  ),

  hemorrhagic_stroke_admissions AS (
    -- Step 2: Identify hospital admissions with a hemorrhagic stroke diagnosis
    SELECT DISTINCT
      hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
      -- ICD-9 codes for subarachnoid, intracerebral, and other intracranial hemorrhage
      SUBSTR(icd_code, 1, 3) IN ('430', '431', '432')
      -- ICD-10 codes for subarachnoid, intracerebral, and other nontraumatic intracranial hemorrhage
      OR SUBSTR(icd_code, 1, 3) IN ('I60', 'I61', 'I62')
  ),

  procedures_in_72h AS (
    -- Step 3: Count procedures within the first 72 hours of the ICU stay for each patient
    SELECT
      cohort.stay_id,
      COUNT(proc.icd_code) AS num_procedures
    FROM base_cohort AS cohort
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
      ON cohort.hadm_id = proc.hadm_id
    WHERE
      -- Filter for procedures that occurred within the first 72 hours of ICU admission
      proc.chartdate <= DATETIME_ADD(cohort.intime, INTERVAL 72 HOUR)
    GROUP BY
      cohort.stay_id
  ),

  final_cohort_data AS (
    -- Step 4: Combine all data points for each patient stay
    SELECT
      cohort.stay_id,
      cohort.los,
      adm.hospital_expire_flag,
      CASE
        WHEN hs.hadm_id IS NOT NULL THEN 'Hemorrhagic Stroke'
        ELSE 'Other'
      END AS patient_group,
      COALESCE(proc.num_procedures, 0) AS num_procedures
    FROM base_cohort AS cohort
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
      ON cohort.hadm_id = adm.hadm_id
    LEFT JOIN
      hemorrhagic_stroke_admissions AS hs
      ON cohort.hadm_id = hs.hadm_id
    LEFT JOIN
      procedures_in_72h AS proc
      ON cohort.stay_id = proc.stay_id
  )

-- Step 5: Aggregate the metrics for the two groups
SELECT
  patient_group,
  APPROX_QUANTILES(num_procedures, 100)[OFFSET(90)] AS p90_diagnostic_procedures_first_72h,
  AVG(los) AS avg_icu_los_days,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS in_hospital_mortality_percent
FROM final_cohort_data
GROUP BY
  patient_group
ORDER BY
  patient_group;