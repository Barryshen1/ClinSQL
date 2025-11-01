WITH patient_cohort AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  WHERE p.gender = 'F'
    AND p.anchor_age = 74
),
heart_failure_admissions AS (
  SELECT DISTINCT a.hadm_id, a.subject_id, a.admittime, a.dischtime,
    a.admission_type,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN patient_cohort p ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di ON a.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%heart failure%'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.dischtime > a.admittime
),
diagnostic_events AS (
  SELECT 
    h.hadm_id,
    h.los_days,
    h.admittime,
    h.dischtime,
    CASE
      WHEN h.admission_type IN ('Emergency', 'Urgent') THEN 'ED/Urgent'
      WHEN h.admission_type = 'Elective' THEN 'Elective'
      ELSE NULL
    END AS admission_category,
    CASE
      WHEN h.los_days >= 1 AND h.los_days < 5 THEN '1–4 days'
      WHEN h.los_days >= 5 AND h.los_days <= 7 THEN '5–7 days'
      ELSE NULL
    END AS los_category
  FROM heart_failure_admissions h
  WHERE h.admission_type IN ('Elective', 'Urgent', 'Emergency')
    AND h.los_days >= 1 AND h.los_days <= 7
),
diagnostics_per_admission AS (
  SELECT
    de.hadm_id,
    de.admission_category,
    de.los_category,
    COUNT(*) AS diagnostic_count
  FROM diagnostic_events de
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.hcpcsevents h ON de.hadm_id = h.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.d_hcpcs d ON h.hcpcs_cd = d.code
  WHERE h.chartdate >= DATE(de.admittime) 
    AND h.chartdate <= DATE(de.dischtime)
    AND (
      d.category = 'IMAGING'
      OR LOWER(d.short_description) LIKE '%ecg%'
      OR LOWER(d.short_description) LIKE '%ekg%'
      OR LOWER(d.short_description) LIKE '%eeg%'
      OR LOWER(d.short_description) LIKE '%pft%'
      OR LOWER(d.short_description) LIKE '%pulmonary function%'
      OR LOWER(d.long_description) LIKE '%ecg%'
      OR LOWER(d.long_description) LIKE '%ekg%'
      OR LOWER(d.long_description) LIKE '%eeg%'
      OR LOWER(d.long_description) LIKE '%pft%'
      OR LOWER(d.long_description) LIKE '%pulmonary function%'
    )
  GROUP BY de.hadm_id, de.admission_category, de.los_category
)
SELECT
  admission_category,
  los_category,
  AVG(diagnostic_count) AS mean_diagnostics_per_admission
FROM diagnostics_per_admission
WHERE admission_category IS NOT NULL AND los_category IS NOT NULL
GROUP BY admission_category, los_category
ORDER BY admission_category, los_category;