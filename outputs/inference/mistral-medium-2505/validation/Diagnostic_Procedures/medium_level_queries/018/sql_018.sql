WITH
-- Get women aged 80-90 with hemorrhagic stroke
hemorrhagic_stroke_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON p.subject_id = d.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 90
    AND (
      -- ICD-9 codes for hemorrhagic stroke
      (d.icd_version = 9 AND d.icd_code LIKE '431.%')
      OR
      -- ICD-10 codes for hemorrhagic stroke
      (d.icd_version = 10 AND d.icd_code LIKE 'I61.%')
    )
),

-- Get their admissions with duration categories
admissions_with_duration AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS stay_days,
    CASE
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 5 AND 7 THEN '5-7 days'
      ELSE NULL
    END AS duration_category
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN hemorrhagic_stroke_patients h ON a.subject_id = h.subject_id
  WHERE TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),

-- Count ultrasounds from HOSP module (HCPCS codes)
hosp_ultrasounds AS (
  SELECT
    h.subject_id,
    h.hadm_id,
    COUNT(DISTINCT h.hcpcs_cd) AS ultrasound_count
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d ON h.hcpcs_cd = d.code
  JOIN admissions_with_duration a ON h.subject_id = a.subject_id AND h.hadm_id = a.hadm_id
  WHERE LOWER(d.long_description) LIKE '%ultrasound%'
    OR LOWER(d.short_description) LIKE '%ultrasound%'
  GROUP BY h.subject_id, h.hadm_id
),

-- Count ultrasounds from ICU module (procedure events)
icu_ultrasounds AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    COUNT(DISTINCT p.itemid) AS ultrasound_count
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` p
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` d ON p.itemid = d.itemid
  JOIN admissions_with_duration a ON p.subject_id = a.subject_id AND p.hadm_id = a.hadm_id
  WHERE LOWER(d.label) LIKE '%ultrasound%'
  GROUP BY p.subject_id, p.hadm_id
),

-- Combine counts from both modules
combined_ultrasounds AS (
  SELECT
    a.duration_category,
    COALESCE(h.ultrasound_count, 0) + COALESCE(i.ultrasound_count, 0) AS total_ultrasounds
  FROM admissions_with_duration a
  LEFT JOIN hosp_ultrasounds h ON a.subject_id = h.subject_id AND a.hadm_id = h.hadm_id
  LEFT JOIN icu_ultrasounds i ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  WHERE a.duration_category IS NOT NULL
)

-- Final aggregation
SELECT
  duration_category,
  COUNT(*) AS admission_count,
  AVG(total_ultrasounds) AS mean_ultrasounds,
  MIN(total_ultrasounds) AS min_ultrasounds,
  MAX(total_ultrasounds) AS max_ultrasounds
FROM combined_ultrasounds
GROUP BY duration_category
ORDER BY duration_category;