WITH
-- Define pneumonia types
pneumonia_codes AS (
  SELECT
    icd_code,
    CASE
      WHEN icd_code IN ('J690', 'J698', 'J699') THEN 'Aspiration'
      WHEN icd_code BETWEEN 'J120' AND 'J189' AND icd_code NOT LIKE 'J69%' THEN 'Community-acquired'
      ELSE NULL
    END AS pneumonia_type
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_version = 10
),

-- Get patient admissions with pneumonia
pneumonia_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    d.icd_code,
    pc.pneumonia_type,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN pneumonia_codes pc ON d.icd_code = pc.icd_code
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
    AND pc.pneumonia_type IS NOT NULL
),

-- Identify ICU status on day 1
icu_status AS (
  SELECT
    pa.subject_id,
    pa.hadm_id,
    MAX(CASE
        WHEN (t.careunit LIKE '%ICU%' AND TIMESTAMP_DIFF(t.intime, pa.admittime, HOUR) <= 24)
          OR (i.intime IS NOT NULL AND TIMESTAMP_DIFF(i.intime, pa.admittime, HOUR) <= 24)
        THEN 1 ELSE 0 END) AS day1_icu
  FROM pneumonia_admissions pa
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.transfers` t ON pa.hadm_id = t.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON pa.hadm_id = i.hadm_id
  GROUP BY pa.subject_id, pa.hadm_id
),

-- Calculate comorbidity count (excluding pneumonia codes)
comorbidity_count AS (
  SELECT
    pa.subject_id,
    pa.hadm_id,
    COUNT(DISTINCT d.icd_code) AS comorbidity_count
  FROM pneumonia_admissions pa
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON pa.hadm_id = d.hadm_id
  JOIN pneumonia_codes pc ON d.icd_code = pc.icd_code
  WHERE pc.pneumonia_type IS NULL  -- Exclude pneumonia codes from comorbidity count
  GROUP BY pa.subject_id, pa.hadm_id
),

-- Combine all data
combined_data AS (
  SELECT
    pa.pneumonia_type,
    CASE
      WHEN pa.los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN pa.los_days BETWEEN 4 AND 7 THEN '4-7 days'
      WHEN pa.los_days >= 8 THEN '8+ days'
      ELSE NULL
    END AS los_group,
    i.day1_icu,
    pa.hospital_expire_flag,
    c.comorbidity_count
  FROM pneumonia_admissions pa
  JOIN icu_status i ON pa.subject_id = i.subject_id AND pa.hadm_id = i.hadm_id
  JOIN comorbidity_count c ON pa.subject_id = c.subject_id AND pa.hadm_id = c.hadm_id
  WHERE pa.los_days >= 1  -- Ensure we have complete LOS data
),

-- Aggregate results
final_results AS (
  SELECT
    pneumonia_type,
    los_group,
    day1_icu,
    COUNT(*) AS patient_count,
    SUM(hospital_expire_flag) AS death_count,
    ROUND(SUM(hospital_expire_flag) / COUNT(*) * 100, 2) AS mortality_rate,
    ROUND(AVG(comorbidity_count), 2) AS avg_comorbidity_count
  FROM combined_data
  GROUP BY pneumonia_type, los_group, day1_icu
)

-- Final output with differences
SELECT
  pneumonia_type,
  los_group,
  day1_icu,
  patient_count,
  death_count,
  mortality_rate,
  avg_comorbidity_count,
  -- Calculate absolute and relative differences
  CASE
    WHEN day1_icu = 1 THEN
      ROUND(mortality_rate - FIRST_VALUE(mortality_rate) OVER (PARTITION BY pneumonia_type, los_group ORDER BY day1_icu), 2)
    ELSE NULL
  END AS abs_diff_with_icu,
  CASE
    WHEN day1_icu = 1 AND
         FIRST_VALUE(mortality_rate) OVER (PARTITION BY pneumonia_type, los_group ORDER BY day1_icu) > 0 THEN
      ROUND((mortality_rate - FIRST_VALUE(mortality_rate) OVER (PARTITION BY pneumonia_type, los_group ORDER BY day1_icu)) /
            NULLIF(FIRST_VALUE(mortality_rate) OVER (PARTITION BY pneumonia_type, los_group ORDER BY day1_icu), 0) * 100, 2)
    ELSE NULL
  END AS rel_diff_with_icu
FROM final_results
ORDER BY pneumonia_type, los_group, day1_icu;