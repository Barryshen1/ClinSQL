WITH 
-- Patient demographics and admission details
patient_info AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    p.anchor_age, 
    p.gender,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    CASE 
      WHEN i.stay_id IS NOT NULL THEN 'ICU'
      ELSE 'non-ICU'
    END AS care_type
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` i 
      ON a.hadm_id = i.hadm_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  WHERE 
    p.anchor_age BETWEEN 71 AND 81 AND p.gender = 'F'
),

-- LOS calculation
los_info AS (
  SELECT 
    subject_id,
    hadm_id,
    care_type,
    TIMESTAMPDIFF(DAY, admittime, COALESCE(dischtime, deathtime)) AS los_days
  FROM 
    patient_info
),

-- LOS quartiles
los_quartiles AS (
  SELECT 
    care_type,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY los_days) AS q1,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY los_days) AS q2,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY los_days) AS q3
  FROM 
    los_info
  GROUP BY 
    care_type
),

-- Categorize patients into LOS quartiles
los_category AS (
  SELECT 
    li.subject_id,
    li.hadm_id,
    li.care_type,
    li.los_days,
    CASE 
      WHEN li.los_days < (SELECT q1 FROM los_quartiles lq WHERE lq.care_type = li.care_type) THEN 'Q1'
      WHEN li.los_days < (SELECT q2 FROM los_quartiles lq WHERE lq.care_type = li.care_type) THEN 'Q2'
      WHEN li.los_days < (SELECT q3 FROM los_quartiles lq WHERE lq.care_type = li.care_type) THEN 'Q3'
      ELSE 'Q4'
    END AS los_quintile
  FROM 
    los_info li
),

-- ICU interventions
icu_interventions AS (
  SELECT 
    subject_id,
    hadm_id,
    COUNT(DISTINCT CASE WHEN itemid = 220050 THEN 1 END) AS ventilation,
    COUNT(DISTINCT CASE WHEN itemid = 221906 THEN 1 END) AS vasopressors,
    COUNT(DISTINCT CASE WHEN itemid = 227488 THEN 1 END) AS rrt
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents`
  GROUP BY 
    subject_id, hadm_id
)

-- Final analysis
SELECT 
  lc.care_type,
  lc.los_quintile,
  AVG(CASE WHEN pi.hospital_expire_flag = 1 THEN 1.0 ELSE 0 END) AS mortality_rate,
  SUM(CASE WHEN ii.ventilation > 0 THEN 1.0 ELSE 0 END) / COUNT(ii.ventilation) AS ventilation_pct,
  SUM(CASE WHEN ii.vasopressors > 0 THEN 1.0 ELSE 0 END) / COUNT(ii.vasopressors) AS vasopressors_pct,
  SUM(CASE WHEN ii.rrt > 0 THEN 1.0 ELSE 0 END) / COUNT(ii.rrt) AS rrt_pct
FROM 
  los_category lc
  JOIN patient_info pi ON lc.subject_id = pi.subject_id AND lc.hadm_id = pi.hadm_id
  LEFT JOIN icu_interventions ii ON lc.subject_id = ii.subject_id AND lc.hadm_id = ii.hadm_id
GROUP BY 
  lc.care_type, lc.los_quintile
ORDER BY 
  lc.care_type, lc.los_quintile;