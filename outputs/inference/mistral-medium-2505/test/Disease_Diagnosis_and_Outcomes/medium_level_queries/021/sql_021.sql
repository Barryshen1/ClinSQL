WITH
-- Get male patients aged 60-70
patient_base AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 60 AND 70
),

-- Get admissions for these patients
admissions_base AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7 days'
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) >= 8 THEN '≥8 days'
    END AS los_category,
    CASE
      WHEN a.deathtime IS NOT NULL THEN TIMESTAMP_DIFF(a.deathtime, a.admittime, DAY)
      ELSE NULL
    END AS time_to_death_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    patient_base p ON a.subject_id = p.subject_id
),

-- Identify postoperative complications
postop_complications AS (
  SELECT DISTINCT
    a.hadm_id,
    a.subject_id
  FROM
    admissions_base a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p ON a.hadm_id = p.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE
    -- Filter for surgical procedures (ICD-10-PCS codes starting with 0)
    p.icd_code LIKE '0%'
    -- And check for complications in diagnoses
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
      WHERE diag.hadm_id = a.hadm_id
      AND (
        -- Example complication codes (would need full list)
        d_diag.icd_code LIKE 'T81%' OR  -- Complications of procedures
        d_diag.icd_code LIKE 'I97%' OR  -- Postprocedural complications
        d_diag.icd_code LIKE 'K91%'      -- Postprocedural complications of digestive system
      )
    )
),

-- Calculate Charlson Comorbidity Index (simplified version)
charlson_scores AS (
  SELECT
    pc.hadm_id,
    pc.subject_id,
    -- This is a simplified calculation - would need full mapping of ICD codes to Charlson weights
    CASE
      WHEN SUM(CASE
        WHEN diag.icd_code IN ('I10', 'I11', 'I12', 'I13', 'I15') THEN 1  -- Hypertension
        WHEN diag.icd_code IN ('E11', 'E13', 'E14') THEN 1              -- Diabetes
        -- Add more conditions as needed
        ELSE 0
      END) <= 3 THEN '≤3'
      WHEN SUM(CASE
        WHEN diag.icd_code IN ('I10', 'I11', 'I12', 'I13', 'I15') THEN 1
        WHEN diag.icd_code IN ('E11', 'E13', 'E14') THEN 1
        ELSE 0
      END) BETWEEN 4 AND 5 THEN '4-5'
      ELSE '>5'
    END AS charlson_category
  FROM
    postop_complications pc
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON pc.hadm_id = diag.hadm_id
  GROUP BY
    pc.hadm_id, pc.subject_id
),

-- Identify ICU vs non-ICU patients
icu_status AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_icu.icustays` i
        WHERE i.hadm_id = a.hadm_id
      ) THEN 'ICU'
      ELSE 'Non-ICU'
    END AS icu_status
  FROM
    admissions_base a
),

-- Final dataset with all needed information
final_dataset AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    i.icu_status,
    a.los_category,
    c.charlson_category,
    a.hospital_expire_flag,
    a.time_to_death_days
  FROM
    admissions_base a
  JOIN
    postop_complications pc ON a.hadm_id = pc.hadm_id AND a.subject_id = pc.subject_id
  JOIN
    icu_status i ON a.hadm_id = i.hadm_id AND a.subject_id = i.subject_id
  JOIN
    charlson_scores c ON a.hadm_id = c.hadm_id AND a.subject_id = c.subject_id
)

-- Final aggregation
SELECT
  icu_status,
  los_category,
  charlson_category,
  COUNT(*) AS total_patients,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality_count,
  ROUND(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) * 100, 2) AS mortality_percentage,
  CASE
    WHEN SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) > 0
    THEN ROUND(PERCENTILE_CONT(time_to_death_days, 0.5) OVER (PARTITION BY icu_status, los_category, charlson_category), 2)
    ELSE NULL
  END AS median_time_to_death_days
FROM
  final_dataset
GROUP BY
  icu_status,
  los_category,
  charlson_category
ORDER BY
  icu_status,
  los_category,
  charlson_category;