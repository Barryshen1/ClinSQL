WITH
  -- Step 1: Identify all hospital admissions for males aged 72-82
  base_admissions AS (
    SELECT
      p.subject_id,
      a.hadm_id,
      (
        EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age
      ) AS age_at_admission,
      TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / (24 * 60 * 60.0) AS los_days,
      a.hospital_expire_flag
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
      JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a ON p.subject_id = a.subject_id
    WHERE
      p.gender = 'M'
      AND (
        EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age
      ) BETWEEN 72 AND 82
      -- Ensure LOS is calculable and positive
      AND a.dischtime IS NOT NULL
      AND a.admittime IS NOT NULL
      AND a.dischtime > a.admittime
  ),
  -- Step 2: Filter the base cohort for admissions with a Heart Failure diagnosis
  hf_cohort AS (
    SELECT DISTINCT
      b.hadm_id,
      b.los_days,
      b.hospital_expire_flag
    FROM
      base_admissions AS b
      JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx ON b.hadm_id = dx.hadm_id
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddx ON dx.icd_code = ddx.icd_code AND dx.icd_version = ddx.icd_version
    WHERE
      LOWER(ddx.long_title) LIKE '%heart failure%'
  ),
  -- Step 3: Pre-calculate the count of diagnoses for each hospital admission
  comorbidity_counts AS (
    SELECT
      hadm_id,
      COUNT(DISTINCT icd_code) AS comorbidity_count
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    GROUP BY
      hadm_id
  ),
  -- Step 4: Combine all data, determine ICU status, and create LOS bins
  final_data AS (
    SELECT
      hf.hadm_id,
      hf.los_days,
      hf.hospital_expire_flag,
      cc.comorbidity_count,
      CASE
        WHEN hf.hadm_id IN (
          SELECT DISTINCT hadm_id FROM `physionet-data.mimiciv_3_1_icu.icustays`
        ) THEN 'ICU'
        ELSE 'Non-ICU'
      END AS admission_group,
      CASE
        WHEN hf.los_days <= 3 THEN '≤3 days'
        WHEN hf.los_days <= 6 THEN '4-6 days'
        WHEN hf.los_days <= 10 THEN '7-10 days'
        ELSE '>10 days'
      END AS los_group
    FROM
      hf_cohort AS hf
      JOIN comorbidity_counts AS cc ON hf.hadm_id = cc.hadm_id
  )
-- Step 5: Aggregate the final data to calculate the requested metrics for each group
SELECT
  admission_group,
  los_group,
  COUNT(hadm_id) AS num_admissions,
  AVG(hospital_expire_flag) AS in_hospital_mortality_rate,
  APPROX_QUANTILES(los_days, 100) [OFFSET(50)] AS median_los_days,
  AVG(comorbidity_count) AS avg_comorbidity_count
FROM
  final_data
GROUP BY
  admission_group,
  los_group
ORDER BY
  -- Order logically by ICU/Non-ICU status and then by the LOS bins
  admission_group,
  CASE
    WHEN los_group = '≤3 days' THEN 1
    WHEN los_group = '4-6 days' THEN 2
    WHEN los_group = '7-10 days' THEN 3
    ELSE 4
  END;