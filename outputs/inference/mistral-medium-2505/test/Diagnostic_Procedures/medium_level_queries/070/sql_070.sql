WITH
-- Get heart failure ICD codes (ICD-9 and ICD-10)
heart_failure_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%heart failure%'
),

-- Get patients with heart failure (males 59-69)
heart_failure_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON p.subject_id = d.subject_id
  JOIN heart_failure_codes hf
    ON d.icd_code = hf.icd_code
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 59 AND 69
),

-- Get radiography/CT HCPCS codes
radiography_ct_codes AS (
  SELECT code
  FROM `physionet-data.mimiciv_3_1_hosp.d_hcpcs`
  WHERE LOWER(long_description) LIKE '%radiography%'
     OR LOWER(long_description) LIKE '%ct%'
     OR LOWER(long_description) LIKE '%computed tomography%'
),

-- Get admissions with duration and ICU use
admissions_with_icu AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS admission_duration,
    CASE WHEN i.hadm_id IS NOT NULL THEN TRUE ELSE FALSE END AS had_icu_stay
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  WHERE a.subject_id IN (SELECT subject_id FROM heart_failure_patients)
),

-- Count radiography/CT procedures per admission
radiography_counts AS (
  SELECT
    a.hadm_id,
    a.admission_duration,
    a.had_icu_stay,
    COUNT(DISTINCT h.hcpcs_cd) AS radiography_ct_count
  FROM admissions_with_icu a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
    ON a.hadm_id = h.hadm_id
  LEFT JOIN radiography_ct_codes r
    ON h.hcpcs_cd = r.code
  GROUP BY a.hadm_id, a.admission_duration, a.had_icu_stay
),

-- Categorize admission durations
duration_categories AS (
  SELECT
    hadm_id,
    radiography_ct_count,
    had_icu_stay,
    CASE
      WHEN admission_duration BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN admission_duration BETWEEN 5 AND 8 THEN '5-8 days'
      ELSE NULL
    END AS duration_category
  FROM radiography_counts
  WHERE admission_duration BETWEEN 1 AND 8
)

-- Calculate percentiles
SELECT
  duration_category,
  had_icu_stay,
  COUNT(hadm_id) AS admission_count,
  PERCENTILE_CONT(radiography_ct_count, 0.25) OVER (PARTITION BY duration_category, had_icu_stay) AS percentile_25,
  PERCENTILE_CONT(radiography_ct_count, 0.5) OVER (PARTITION BY duration_category, had_icu_stay) AS percentile_50,
  PERCENTILE_CONT(radiography_ct_count, 0.75) OVER (PARTITION BY duration_category, had_icu_stay) AS percentile_75
FROM duration_categories
GROUP BY duration_category, had_icu_stay, hadm_id, radiography_ct_count
ORDER BY duration_category, had_icu_stay;