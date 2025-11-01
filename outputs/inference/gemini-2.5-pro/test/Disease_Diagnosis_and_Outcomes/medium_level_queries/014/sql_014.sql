WITH
  -- Step 1: Find all hospital admissions for male patients aged 77-87 with a Heart Failure diagnosis.
  distinct_hf_admissions AS (
    SELECT DISTINCT
      adm.subject_id,
      adm.hadm_id,
      adm.admittime,
      adm.dischtime,
      adm.hospital_expire_flag
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      ON adm.subject_id = pat.subject_id
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      ON adm.hadm_id = dx.hadm_id
    WHERE
      pat.gender = 'M'
      AND (DATETIME_DIFF(adm.admittime, DATETIME(pat.anchor_year, 1, 1, 0, 0, 0), YEAR) + pat.anchor_age) BETWEEN 77 AND 87
      AND (
        (dx.icd_version = 9 AND dx.icd_code LIKE '428%')
        OR (dx.icd_version = 10 AND dx.icd_code LIKE 'I50%')
      )
  ),

  -- Step 2: Flag admissions with a diagnosis of CKD or Diabetes.
  comorbidities AS (
    SELECT
      hadm_id,
      MAX(
        CASE
          WHEN (icd_version = 9 AND icd_code LIKE '585%') OR (icd_version = 10 AND icd_code LIKE 'N18%')
          THEN 1
          ELSE 0
        END
      ) AS ckd_flag,
      MAX(
        CASE
          WHEN
            (icd_version = 9 AND icd_code LIKE '250%')
            OR (
              icd_version = 10 AND (
                icd_code LIKE 'E08%'
                OR icd_code LIKE 'E09%'
                OR icd_code LIKE 'E10%'
                OR icd_code LIKE 'E11%'
                OR icd_code LIKE 'E12%'
                OR icd_code LIKE 'E13%'
              )
            )
          THEN 1
          ELSE 0
        END
      ) AS diabetes_flag
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    GROUP BY
      hadm_id
  ),

  -- Step 3: Identify admissions that included an ICU stay within the first 24 hours.
  day1_icu_admissions AS (
    SELECT DISTINCT
      icu.hadm_id
    FROM
      `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
      ON icu.hadm_id = adm.hadm_id
    WHERE
      icu.intime <= DATETIME_ADD(adm.admittime, INTERVAL 24 HOUR)
  ),

  -- Step 4: Combine the cohort with comorbidity and ICU status, and calculate LOS.
  final_cohort AS (
    SELECT
      hf.hadm_id,
      hf.hospital_expire_flag,
      -- Calculate hospital LOS in days
      DATETIME_DIFF(hf.dischtime, hf.admittime, HOUR) / 24.0 AS los_days,
      -- Create ICU group based on whether the hadm_id is in our day-1 ICU list
      CASE
        WHEN d1_icu.hadm_id IS NOT NULL THEN 'Day-1 ICU'
        ELSE 'Non-ICU'
      END AS icu_group,
      -- Add comorbidity flags, defaulting to 0 if no record exists
      COALESCE(cm.ckd_flag, 0) AS ckd_flag,
      COALESCE(cm.diabetes_flag, 0) AS diabetes_flag
    FROM
      distinct_hf_admissions AS hf
    LEFT JOIN
      comorbidities AS cm
      ON hf.hadm_id = cm.hadm_id
    LEFT JOIN
      day1_icu_admissions AS d1_icu
      ON hf.hadm_id = d1_icu.hadm_id
  )

-- Step 5: Aggregate the final cohort by ICU and LOS groups to calculate the required metrics.
SELECT
  icu_group,
  CASE
    WHEN los_days >= 1 AND los_days <= 3
    THEN '1-3 days'
    WHEN los_days > 3 AND los_days <= 7
    THEN '4-7 days'
    WHEN los_days > 7
    THEN '>=8 days'
  END AS los_group,
  COUNT(hadm_id) AS number_of_admissions,
  -- Calculate in-hospital mortality percentage
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS in_hospital_mortality_pct,
  -- Calculate median length of stay in days
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(50)], 2) AS median_los_days,
  -- Calculate CKD prevalence percentage
  ROUND(AVG(ckd_flag) * 100, 2) AS ckd_prevalence_pct,
  -- Calculate Diabetes prevalence percentage
  ROUND(AVG(diabetes_flag) * 100, 2) AS diabetes_prevalence_pct
FROM
  final_cohort
WHERE
  -- Filter to include only the specified LOS buckets
  los_days >= 1
GROUP BY
  icu_group,
  los_group
ORDER BY
  icu_group,
  -- Custom order for the LOS groups to ensure logical sorting
  CASE los_group
    WHEN '1-3 days' THEN 1
    WHEN '4-7 days' THEN 2
    WHEN '>=8 days' THEN 3
  END;