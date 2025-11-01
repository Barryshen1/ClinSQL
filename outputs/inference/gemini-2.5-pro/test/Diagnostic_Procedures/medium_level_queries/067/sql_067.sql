WITH
  -- Step 1: Define the base cohort of male patients, aged 39-49, with a hospital LOS of 1-7 days.
  cohort_admissions AS (
    SELECT
      p.subject_id,
      a.hadm_id,
      DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON p.subject_id = a.subject_id
    WHERE
      p.gender = 'M'
      AND p.anchor_age BETWEEN 39 AND 49
      AND DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
  ),
  -- Step 2: Identify all admissions with an Acute Coronary Syndrome (ACS) diagnosis.
  acs_diagnoses AS (
    SELECT
      dx.hadm_id,
      dx.seq_num
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dx
      ON dx.icd_code = d_dx.icd_code
      AND dx.icd_version = d_dx.icd_version
    WHERE
      -- Use a combination of specific codes and broader text search for robustness
      (
        (dx.icd_version = 9 AND dx.icd_code LIKE '410%') -- Acute MI
        OR (dx.icd_version = 10 AND dx.icd_code LIKE 'I21%') -- Acute MI
        OR (dx.icd_version = 9 AND dx.icd_code = '4111') -- Unstable Angina
        OR (dx.icd_version = 10 AND dx.icd_code = 'I200') -- Unstable Angina
        OR LOWER(d_dx.long_title) LIKE '%acute coronary syndrome%'
        OR LOWER(d_dx.long_title) LIKE '%myocardial infarction%'
      )
  ),
  -- Step 3: Filter the cohort for ACS patients and determine if ACS was a primary diagnosis.
  acs_cohort AS (
    SELECT
      ca.hadm_id,
      ca.los_days,
      MIN(adx.seq_num) AS min_acs_seq_num
    FROM
      cohort_admissions AS ca
    INNER JOIN
      acs_diagnoses AS adx
      ON ca.hadm_id = adx.hadm_id
    GROUP BY
      ca.hadm_id,
      ca.los_days
  ),
  -- Step 4: Collect all instances of ultrasound or echocardiogram procedures from various tables.
  ultrasound_procedures AS (
    -- Source 1: ICD-coded procedures
    SELECT
      proc.hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS d_proc
      ON proc.icd_code = d_proc.icd_code
      AND proc.icd_version = d_proc.icd_version
    WHERE
      LOWER(d_proc.long_title) LIKE '%ultrasound%' OR LOWER(d_proc.long_title) LIKE '%echocar%'
    UNION ALL
    -- Source 2: HCPCS-coded procedures
    SELECT
      hcpcs.hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.hcpcsevents` AS hcpcs
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.d_hcpcs` AS d_hcpcs
      ON hcpcs.hcpcs_cd = d_hcpcs.code
    WHERE
      LOWER(d_hcpcs.long_description) LIKE '%ultrasound%' OR LOWER(d_hcpcs.long_description) LIKE '%echocar%'
    UNION ALL
    -- Source 3: ICU procedure events
    SELECT
      p_icu.hadm_id
    FROM
      `physionet-data.mimiciv_3_1_icu.procedureevents` AS p_icu
    INNER JOIN
      `physionet-data.mimiciv_3_1_icu.d_items` AS d_icu
      ON p_icu.itemid = d_icu.itemid
    WHERE
      LOWER(d_icu.label) LIKE '%ultrasound%' OR LOWER(d_icu.label) LIKE '%echocar%'
  ),
  -- Step 5: Count the number of ultrasounds per admission.
  ultrasound_counts AS (
    SELECT
      hadm_id,
      COUNT(*) AS ultrasound_count
    FROM
      ultrasound_procedures
    GROUP BY
      hadm_id
  ),
  -- Step 6: Join the final cohort with procedure counts and create stratification columns.
  final_data AS (
    SELECT
      ac.hadm_id,
      COALESCE(uc.ultrasound_count, 0) AS ultrasound_count,
      CASE
        WHEN ac.los_days BETWEEN 1 AND 4
        THEN '1-4 days'
        WHEN ac.los_days BETWEEN 5 AND 7
        THEN '5-7 days'
      END AS los_group,
      CASE
        WHEN ac.min_acs_seq_num = 1
        THEN 'Primary ACS'
        ELSE 'Secondary ACS'
      END AS acs_type
    FROM
      acs_cohort AS ac
    LEFT JOIN
      ultrasound_counts AS uc
      ON ac.hadm_id = uc.hadm_id
  )
-- Step 7: Final aggregation to compute percentiles for each stratum.
SELECT
  los_group,
  acs_type,
  COUNT(hadm_id) AS number_of_admissions,
  APPROX_QUANTILES(ultrasound_count, 100) [OFFSET(25)] AS p25_ultrasounds_per_admission,
  APPROX_QUANTILES(ultrasound_count, 100) [OFFSET(50)] AS p50_ultrasounds_per_admission,
  APPROX_QUANTILES(ultrasound_count, 100) [OFFSET(75)] AS p75_ultrasounds_per_admission
FROM
  final_data
GROUP BY
  los_group,
  acs_type
ORDER BY
  los_group,
  acs_type;