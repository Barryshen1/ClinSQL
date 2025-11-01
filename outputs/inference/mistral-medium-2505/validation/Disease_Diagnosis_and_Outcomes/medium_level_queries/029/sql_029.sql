WITH
-- Define age at admission
patient_age AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    anchor_year,
    EXTRACT(YEAR FROM CURRENT_DATE()) - anchor_year + anchor_age AS age
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
),

-- Get first admission for each patient
first_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS admission_rank
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN patient_age p ON a.subject_id = p.subject_id
  WHERE p.gender = 'F' AND p.age BETWEEN 57 AND 67
),

-- Filter for first admissions only
filtered_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    hospital_expire_flag,
    los_days,
    CASE WHEN los_days <= 7 THEN '≤7 days' ELSE '>7 days' END AS los_category
  FROM first_admissions
  WHERE admission_rank = 1
),

-- First identify sepsis cases
sepsis_identification AS (
  SELECT
    di.subject_id,
    di.hadm_id,
    CASE
      WHEN
        -- Septic shock codes
        (d.icd_code IN ('785.52', '995.92', 'R65.21', 'R57.2') AND d.icd_version IN (9, 10)) THEN 'Septic shock'
      WHEN
        -- Sepsis without shock codes
        (d.icd_code IN ('995.91', '038.91', 'R65.20', 'A41.9') AND d.icd_version IN (9, 10)) THEN 'Sepsis'
      ELSE NULL
    END AS sepsis_type
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE sepsis_type IS NOT NULL
),

-- Join with filtered admissions to get sepsis cases with all needed fields
sepsis_cases AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.los_category,
    f.hospital_expire_flag,
    s.sepsis_type
  FROM filtered_admissions f
  JOIN sepsis_identification s ON f.hadm_id = s.hadm_id
),

-- Calculate Charlson Comorbidity Index (simplified version)
charlson_scores AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.sepsis_type,
    s.los_category,
    s.hospital_expire_flag,
    -- Simplified Charlson score calculation
    CASE
      WHEN SUM(CASE WHEN di.icd_code LIKE '410.%' OR di.icd_code LIKE '412%' OR di.icd_code LIKE 'I21.%' OR di.icd_code LIKE 'I22.%' THEN 1 ELSE 0 END) > 0 THEN 1 ELSE 0 END +
    CASE WHEN SUM(CASE WHEN di.icd_code LIKE '428.%' OR di.icd_code LIKE 'I50.%' THEN 1 ELSE 0 END) > 0 THEN 1 ELSE 0 END +
    CASE WHEN SUM(CASE WHEN di.icd_code LIKE '496%' OR di.icd_code LIKE 'J44.%' THEN 1 ELSE 0 END) > 0 THEN 1 ELSE 0 END +
    CASE WHEN SUM(CASE WHEN di.icd_code LIKE '250.%' OR di.icd_code LIKE 'E11.%' OR di.icd_code LIKE 'E13.%' THEN 1 ELSE 0 END) > 0 THEN 1 ELSE 0 END AS charlson_score
  FROM sepsis_cases s
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON s.hadm_id = di.hadm_id
  GROUP BY s.subject_id, s.hadm_id, s.sepsis_type, s.los_category, s.hospital_expire_flag
),

-- Categorize Charlson scores
charlson_categories AS (
  SELECT
    subject_id,
    hadm_id,
    sepsis_type,
    los_category,
    hospital_expire_flag,
    CASE
      WHEN charlson_score <= 3 THEN '≤3'
      WHEN charlson_score BETWEEN 4 AND 5 THEN '4-5'
      ELSE '>5'
    END AS charlson_category
  FROM charlson_scores
),

-- Final aggregation
final_results AS (
  SELECT
    sepsis_type,
    los_category,
    charlson_category,
    COUNT(*) AS total_patients,
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS deaths,
    ROUND(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS mortality_percentage
  FROM charlson_categories
  GROUP BY sepsis_type, los_category, charlson_category
)

-- Calculate differences
SELECT
  sepsis_type,
  los_category,
  charlson_category,
  total_patients,
  deaths,
  mortality_percentage,
  -- Absolute difference (compared to reference group - sepsis, ≤7 days, ≤3 Charlson)
  mortality_percentage - FIRST_VALUE(mortality_percentage) OVER (
    PARTITION BY sepsis_type
    ORDER BY
      CASE WHEN los_category = '≤7 days' AND charlson_category = '≤3' THEN 0 ELSE 1 END,
      los_category,
      charlson_category
  ) AS absolute_difference,
  -- Relative difference (risk ratio)
  ROUND(
    mortality_percentage / NULLIF(
      FIRST_VALUE(mortality_percentage) OVER (
        PARTITION BY sepsis_type
        ORDER BY
          CASE WHEN los_category = '≤7 days' AND charlson_category = '≤3' THEN 0 ELSE 1 END,
          los_category,
          charlson_category
      ),
      0
    ),
    2
  ) AS relative_difference
FROM final_results
ORDER BY sepsis_type, los_category, charlson_category;