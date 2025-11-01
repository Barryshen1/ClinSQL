WITH base_population AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 47 AND 57
),

-- Get creatinine measurements
creatinine AS (
  SELECT 
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum AS creatinine_value
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  WHERE dli.label = 'Creatinine'
    AND le.valuenum IS NOT NULL
),

-- Filter to only include patients with at least 2 creatinine measurements in first 72 hours
eligible_patients AS (
  SELECT 
    bp.hadm_id
  FROM base_population bp
  INNER JOIN creatinine c
    ON bp.hadm_id = c.hadm_id
      AND c.charttime <= DATETIME_ADD(bp.admittime, INTERVAL 72 HOUR)
  GROUP BY bp.hadm_id
  HAVING COUNT(*) >= 2
),

-- Get baseline creatinine (minimum value in first 24 hours)
baseline_creatinine AS (
  SELECT 
    c.hadm_id,
    MIN(c.creatinine_value) AS baseline_value
  FROM creatinine c
  INNER JOIN base_population bp
    ON c.hadm_id = bp.hadm_id
  WHERE c.charttime <= DATETIME_ADD(bp.admittime, INTERVAL 24 HOUR)
  GROUP BY c.hadm_id
),

-- Define AKI (within first 72 hours of admission)
aki_definition AS (
  SELECT 
    bp.hadm_id,
    bp.subject_id,
    bp.admittime,
    bp.dischtime,
    bp.hospital_expire_flag,
    MAX(CASE 
          WHEN c.charttime <= DATETIME_ADD(bp.admittime, INTERVAL 72 HOUR) 
            AND bc.baseline_value IS NOT NULL
            AND (c.creatinine_value >= bc.baseline_value * 1.5 
                 OR c.creatinine_value >= bc.baseline_value + 0.3)
          THEN 1 
          ELSE 0 
        END) AS has_aki
  FROM base_population bp
  INNER JOIN eligible_patients ep ON bp.hadm_id = ep.hadm_id
  LEFT JOIN creatinine c 
    ON bp.hadm_id = c.hadm_id
      AND c.charttime >= bp.admittime
  LEFT JOIN baseline_creatinine bc 
    ON bp.hadm_id = bc.hadm_id
  GROUP BY bp.hadm_id, bp.subject_id, bp.admittime, bp.dischtime, bp.hospital_expire_flag
),

-- Calculate laboratory instability score (standard deviation of creatinine in first 72 hours)
lab_instability AS (
  SELECT 
    c.hadm_id,
    STDDEV(c.creatinine_value) AS instability_score
  FROM creatinine c
  INNER JOIN base_population bp
    ON c.hadm_id = bp.hadm_id
  WHERE c.charttime <= DATETIME_ADD(bp.admittime, INTERVAL 72 HOUR)
  GROUP BY c.hadm_id
),

-- Identify critical events (dialysis)
critical_events AS (
  SELECT 
    pi.hadm_id,
    1 AS has_dialysis
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip
    ON pi.icd_code = dip.icd_code 
    AND pi.icd_version = dip.icd_version
  WHERE dip.long_title LIKE '%dialysis%'
  GROUP BY pi.hadm_id
),

-- Calculate length of stay
los AS (
  SELECT 
    hadm_id,
    DATETIME_DIFF(dischtime, admittime, HOUR) / 24.0 AS los_days
  FROM base_population
)

-- Final comparison
SELECT 
  CASE WHEN ad.has_aki = 1 THEN 'AKI' ELSE 'Control' END AS group_name,
  AVG(CASE WHEN ad.has_aki = 1 THEN li.instability_score ELSE NULL END) AS mean_instability_score,
  AVG(COALESCE(ce.has_dialysis, 0)) AS critical_event_frequency,
  AVG(l.los_days) AS avg_los,
  AVG(ad.hospital_expire_flag) AS mortality_rate
FROM aki_definition ad
LEFT JOIN lab_instability li 
  ON ad.hadm_id = li.hadm_id
LEFT JOIN critical_events ce 
  ON ad.hadm_id = ce.hadm_id
LEFT JOIN los l 
  ON ad.hadm_id = l.hadm_id
GROUP BY group_name;