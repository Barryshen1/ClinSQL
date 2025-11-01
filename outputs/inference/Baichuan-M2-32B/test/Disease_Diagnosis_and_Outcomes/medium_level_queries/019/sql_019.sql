WITH
  -- Step 1: Compute birth date and age at admission, including gender
  patients_with_age AS (
    SELECT
      p.subject_id,
      p.anchor_year,
      p.anchor_age,
      p.gender,   -- Added to use in gender filter
      DATE_SUB(CAST(CONCAT(p.anchor_year, '-01-01') AS DATE), INTERVAL p.anchor_age YEAR) AS birth_date
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  ),
  -- Step 2: HF admissions for males aged 53-63
  hf_admissions AS (
    SELECT
      a.hadm_id,
      a.subject_id,
      a.admittime,
      a.dischtime,
      a.hospital_expire_flag,
      a.discharge_location,
      -- Compute age at admission
      TIMESTAMP_DIFF(a.admittime, p.birth_date, YEAR) AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN patients_with_age p ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id AND a.subject_id = d.subject_id
    WHERE p.gender = 'M'   -- Fixed: now using patients table for gender
      AND TIMESTAMP_DIFF(a.admittime, p.birth_date, YEAR) BETWEEN 53 AND 63
      AND d.icd_version = 9
      AND d.icd_code IN (
        '402.01', '402.11', '402.91', '404.01', '404.03', '404.11', '404.13', '404.91', '404.93',
        '428.0', '428.1', '428.2', '428.3', '428.4', '428.9', '429.0', '429.1', '429.2', '429.3', '429.4', '429.8', '429.9', '785.0', '785.71'
      )
    GROUP BY a.hadm_id, a.subject_id, a.admittime, a.dischtime, a.hospital_expire_flag, a.discharge_location, p.birth_date
  ),
  -- Step 3: Define Charlson ICD-9 codes (simplified, we'll include a few for example)
  charlson_icd9_codes AS (
    SELECT '410' AS icd9_code, 'Myocardial infarction' AS condition_name
    UNION ALL SELECT '402.01', 'Congestive heart failure'
    UNION ALL SELECT '404.01', 'Congestive heart failure'
    UNION ALL SELECT '428.0', 'Congestive heart failure'
    UNION ALL SELECT '428.1', 'Congestive heart failure'
    UNION ALL SELECT '428.2', 'Congestive heart failure'
    UNION ALL SELECT '428.3', 'Congestive heart failure'
    UNION ALL SELECT '428.4', 'Congestive heart failure'
    UNION ALL SELECT '428.9', 'Congestive heart failure'
    UNION ALL SELECT '429.0', 'Congestive heart failure'
    UNION ALL SELECT '429.1', 'Congestive heart failure'
    UNION ALL SELECT '429.2', 'Congestive heart failure'
    UNION ALL SELECT '429.3', 'Congestive heart failure'
    UNION ALL SELECT '429.4', 'Congestive heart failure'
    UNION ALL SELECT '429.8', 'Congestive heart failure'
    UNION ALL SELECT '429.9', 'Congestive heart failure'
    UNION ALL SELECT '785.0', 'Congestive heart failure'
    UNION ALL SELECT '785.71', 'Congestive heart failure'
    UNION ALL SELECT '414', 'Peripheral vascular disease'
    -- ... add more conditions as needed
  ),
  -- Step 4: Map diagnoses to Charlson conditions
  comorbidity_conditions AS (
    SELECT
      d.hadm_id,
      c.condition_name
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN charlson_icd9_codes c
      ON d.icd_code LIKE CONCAT(c.icd9_code, '%') -- for codes that are prefixes
      AND d.icd_version = 9
    GROUP BY d.hadm_id, c.condition_name
  ),
  -- Step 5: Count comorbidities per admission
  comorbidity_counts AS (
    SELECT
      hadm_id,
      COUNT(DISTINCT condition_name) AS charlson_count
    FROM comorbidity_conditions
    GROUP BY hadm_id
  ),
  -- Step 6: Compute LOS and categorize
  los_groups AS (
    SELECT
      hadm_id,
      TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los_days,
      CASE
        WHEN TIMESTAMP_DIFF(dischtime, admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
        WHEN TIMESTAMP_DIFF(dischtime, admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
        WHEN TIMESTAMP_DIFF(dischtime, admittime, DAY) >= 8 THEN '>=8'
        ELSE 'Unknown'
      END AS los_group
    FROM hf_admissions
  ),
  -- Step 7: Categorize Charlson count
  charlson_groups AS (
    SELECT
      hadm_id,
      charlson_count,
      CASE
        WHEN charlson_count <= 3 THEN '≤3'
        WHEN charlson_count BETWEEN 4 AND 5 THEN '4-5'
        WHEN charlson_count > 5 THEN '>5'
        ELSE 'Unknown'
      END AS charlson_group
    FROM comorbidity_counts
  ),
  -- Step 8: Map discharge location to categories
  discharge_dest AS (
    SELECT
      hadm_id,
      discharge_location,
      CASE
        WHEN discharge_location IN ('Home', 'Home Health Care') THEN 'Home'
        WHEN discharge_location IN ('Rehabilitation Facility') THEN 'Rehab'
        WHEN discharge_location IN ('Skilled Nursing Facility') THEN 'SNF'
        WHEN discharge_location IN ('Hospice') THEN 'Hospice'
        ELSE 'Other'
      END AS discharge_category
    FROM hf_admissions
  ),
  -- Step 9: Combine all for final grouping
  final_data AS (
    SELECT
      l.los_group,
      c.charlson_group,
      a.hospital_expire_flag,
      d.discharge_category
    FROM hf_admissions a
    JOIN los_groups l ON a.hadm_id = l.hadm_id
    JOIN charlson_groups c ON a.hadm_id = c.hadm_id
    JOIN discharge_dest d ON a.hadm_id = d.hadm_id
  )
-- Step 10: Group by LOS group and Charlson group, and compute metrics
SELECT
  los_group,
  charlson_group,
  COUNT(*) AS total_admissions,
  SUM(CAST(hospital_expire_flag AS INT)) AS deaths,
  (SUM(CAST(hospital_expire_flag AS INT)) / COUNT(*) * 100) AS mortality_rate_percent,
  -- Discharge destination percentages
  SUM(CASE WHEN discharge_category = 'Home' THEN 1 ELSE 0 END) / COUNT(*) * 100 AS pct_home,
  SUM(CASE WHEN discharge_category = 'Rehab' THEN 1 ELSE 0 END) / COUNT(*) * 100 AS pct_rehab,
  SUM(CASE WHEN discharge_category = 'SNF' THEN 1 ELSE 0 END) / COUNT(*) * 100 AS pct_snf,
  SUM(CASE WHEN discharge_category = 'Hospice' THEN 1 ELSE 0 END) / COUNT(*) * 100 AS pct_hospice
FROM final_data
GROUP BY los_group, charlson_group
ORDER BY los_group, charlson_group;