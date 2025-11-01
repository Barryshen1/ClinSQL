WITH base_cohort AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_adm
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
),
filtered_cohort AS (
  SELECT * 
  FROM base_cohort 
  WHERE age_adm BETWEEN 47 AND 57
),
aki_diagnoses AS (
  SELECT DISTINCT hadm_id 
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
  WHERE 
    (icd_version = 9 AND icd_code LIKE '584%') 
    OR (icd_version = 10 AND icd_code LIKE 'N17%')
),
aki_cohort AS (
  SELECT 
    f.*,
    CASE WHEN a.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS aki
  FROM filtered_cohort f
  LEFT JOIN aki_diagnoses a 
    ON f.hadm_id = a.hadm_id
),
-- Lab instability score (AKI group only)
aki_labs AS (
  SELECT 
    a.hadm_id,
    CASE 
      WHEN l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper 
      THEN 1 ELSE 0 
    END AS abnormal
  FROM aki_cohort a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON a.hadm_id = l.hadm_id
  WHERE 
    a.aki = 1
    AND l.charttime BETWEEN a.admittime AND DATETIME_ADD(a.admittime, INTERVAL 72 HOUR)
    AND l.itemid IN (50912, 51006, 50971, 50983)  -- Creatinine, BUN, Potassium, Sodium
    AND l.valuenum IS NOT NULL
),
aki_labs_agg AS (
  SELECT 
    hadm_id,
    SUM(abnormal) AS instability_score
  FROM aki_labs
  GROUP BY hadm_id
),
aki_instability AS (
  SELECT 
    a.hadm_id,
    COALESCE(l.instability_score, 0) AS instability_score  -- 0 if no labs
  FROM aki_cohort a
  LEFT JOIN aki_labs_agg l 
    ON a.hadm_id = l.hadm_id
  WHERE a.aki = 1
),
-- ICU stays (for critical events)
icu_stays AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
cohort_with_icu AS (
  SELECT 
    a.*,
    CASE WHEN i.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS had_icu
  FROM aki_cohort a
  LEFT JOIN icu_stays i 
    ON a.hadm_id = i.hadm_id
),
-- Final metrics
cohort_metrics AS (
  SELECT 
    c.*,
    -- Critical event: death OR ICU admission
    CASE WHEN c.hospital_expire_flag = 1 OR c.had_icu = 1 THEN 1 ELSE 0 END AS critical_event,
    -- LOS in days (exact)
    DATETIME_DIFF(c.dischtime, c.admittime, HOUR) / 24.0 AS los_days
  FROM cohort_with_icu c
),
-- Combine instability score
final_cohort AS (
  SELECT 
    m.*,
    i.instability_score
  FROM cohort_metrics m
  LEFT JOIN aki_instability i 
    ON m.hadm_id = i.hadm_id  -- Only non-null for AKI group
)
-- Aggregate by group (AKI vs. Control)
SELECT 
  CASE 
    WHEN aki = 1 THEN 'AKI' 
    ELSE 'Control' 
  END AS group_name,
  COUNT(*) AS n_admissions,
  AVG(instability_score) AS mean_instability_score,  -- NULL for Control
  AVG(critical_event) AS critical_event_frequency,
  AVG(los_days) AS avg_los_days,
  AVG(hospital_expire_flag) AS mortality_rate
FROM final_cohort
GROUP BY aki, group_name
ORDER BY aki DESC;