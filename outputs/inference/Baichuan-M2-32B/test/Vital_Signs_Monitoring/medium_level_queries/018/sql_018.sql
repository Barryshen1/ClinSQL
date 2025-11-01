WITH systolic_bp_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE label LIKE '%Systolic%' 
    AND category = 'Vital Signs'
    AND unitname = 'mmHg'
),
cohort_icustays AS (
  SELECT 
    i.subject_id, 
    i.hadm_id, 
    i.stay_id, 
    i.intime,
    p.anchor_year - p.anchor_age AS birth_year,
    EXTRACT(YEAR FROM i.intime) - (p.anchor_year - p.anchor_age) AS age_at_icu
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND EXTRACT(YEAR FROM i.intime) - (p.anchor_year - p.anchor_age) BETWEEN 75 AND 85
),
systolic_bp_measurements AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.intime,
    ce.charttime,
    ce.valuenum AS systolic_bp
  FROM cohort_icustays c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.subject_id = ce.subject_id
    AND c.stay_id = ce.stay_id
  WHERE ce.itemid IN (SELECT itemid FROM systolic_bp_items)
    AND ce.charttime BETWEEN c.intime AND c.intime + INTERVAL 48 HOUR
    AND ce.valuenum IS NOT NULL
),
stay_mean_sbp AS (
  SELECT 
    subject_id,
    hadm_id,
    stay_id,
    AVG(systolic_bp) AS mean_sbp
  FROM systolic_bp_measurements
  GROUP BY subject_id, hadm_id, stay_id
),
cohort_stats AS (
  SELECT 
    COUNT(*) AS total_stays,
    SUM(CASE WHEN mean_sbp <= 140 THEN 1 ELSE 0 END) AS count_le_140
  FROM stay_mean_sbp
)
SELECT 
  (count_le_140 * 100.0) / total_stays AS percentile_140
FROM cohort_stats;