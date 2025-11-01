WITH gi_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE 
    REGEXP_CONTAINS(LOWER(long_title), r'lower (gi|gastrointestinal) (bleed|hemorrhage)') OR
    REGEXP_CONTAINS(LOWER(long_title), r'gastrointestinal hemorrhage,? lower')
),
admissions_data AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag AS mortality,
    p.gender,
    p.anchor_age,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE WHEN di.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_gi_bleed
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  LEFT JOIN (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    INNER JOIN gi_codes 
      ON di.icd_code = gi_codes.icd_code 
      AND di.icd_version = gi_codes.icd_version
  ) di ON a.hadm_id = di.hadm_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 65 AND 75
),
lab_critical AS (
  SELECT 
    l.hadm_id,
    COUNT(*) AS critical_lab_count
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN admissions_data ad 
    ON l.hadm_id = ad.hadm_id
  WHERE 
    l.charttime BETWEEN ad.admittime AND DATETIME_ADD(ad.admittime, INTERVAL 72 HOUR)
    AND l.flag IS NOT NULL
    AND l.flag != 'Normal'
  GROUP BY l.hadm_id
),
combined_data AS (
  SELECT 
    ad.*,
    COALESCE(lc.critical_lab_count, 0) AS critical_lab_count
  FROM admissions_data ad
  LEFT JOIN lab_critical lc 
    ON ad.hadm_id = lc.hadm_id
),
cohort AS (
  SELECT * FROM combined_data WHERE has_gi_bleed = 1
),
comparison AS (
  SELECT * FROM combined_data WHERE has_gi_bleed = 0
),
cohort_agg AS (
  SELECT
    APPROX_QUANTILES(critical_lab_count, 100)[OFFSET(25)] AS percentile_25_lab_instability,
    AVG(critical_lab_count) AS avg_critical_lab_cohort,
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los,
    (SUM(mortality) / COUNT(*)) * 100 AS mortality_rate
  FROM cohort
),
comparison_agg AS (
  SELECT
    AVG(critical_lab_count) AS avg_critical_lab_comparison
  FROM comparison
)
SELECT
  percentile_25_lab_instability,
  avg_critical_lab_cohort,
  avg_critical_lab_comparison,
  median_los,
  mortality_rate
FROM cohort_agg, comparison_agg;