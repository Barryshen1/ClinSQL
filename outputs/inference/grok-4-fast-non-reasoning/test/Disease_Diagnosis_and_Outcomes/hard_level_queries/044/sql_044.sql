WITH cohort AS (
  -- Base cohort: females 59-69 with cardiac arrest admission and ICU stay
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    -- Approximate 30-day mortality: use in-hospital death as proxy
    a.hospital_expire_flag AS mortality_30d,
    -- Hospital LOS in days
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- CV complications: any non-arrest I00-I99
    MAX(CASE WHEN di.icd_version = '10' AND di.icd_code LIKE 'I[0-9][0-9]' 
             AND di.icd_code NOT LIKE 'I46%' THEN 1 ELSE 0 END) AS has_cv_comp,
    -- Neurologic complications: any G00-G99
    MAX(CASE WHEN di.icd_version = '10' AND di.icd_code LIKE 'G[0-9][0-9]' THEN 1 ELSE 0 END) AS has_neuro_comp
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
    AND di.icd_version = '10'  -- Prioritize ICD-10
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.transfers` t 
    ON a.subject_id = t.subject_id AND a.hadm_id = t.hadm_id
    AND t.eventtype = 'admit'
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
    ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND di.icd_code LIKE 'I46%'  -- Cardiac arrest
    AND t.careunit IN ('SICU', 'MICU', 'CCU', 'NICU')  -- Ensure ICU inpatient
    AND a.admission_type IN ('ELECTIVE', 'EMERGENCY', 'URGENT')
    AND i.los > 0
    AND a.admittime < a.dischtime  -- Valid admission
  GROUP BY p.subject_id, a.hadm_id, p.gender, p.anchor_age, a.admittime, a.dischtime, a.deathtime, a.hospital_expire_flag
  -- Dedup: first admission per patient
  QUALIFY ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) = 1
),

vitals AS (
  -- Simple composite risk score: average of per-vital first 24h averages
  SELECT 
    c.subject_id,
    c.hadm_id,
    AVG(vital_avg) AS composite_score
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
    ON c.subject_id = i.subject_id AND c.hadm_id = i.hadm_id
  INNER JOIN (
    SELECT 
      subject_id, hadm_id, stay_id,
      AVG(CASE itemid 
        WHEN 220045 THEN valuenum  -- Heart rate
        WHEN 220179 THEN valuenum  -- SBP
        WHEN 223761 THEN valuenum  -- Temp C
        WHEN 220210 THEN valuenum  -- RR
        WHEN 223900 THEN valuenum  -- GCS total
      END) AS vital_avg
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    WHERE valuenum IS NOT NULL
      AND itemid IN (220045, 220179, 223761, 220210, 223900)
    GROUP BY subject_id, hadm_id, stay_id
  ) v ON c.subject_id = v.subject_id AND c.hadm_id = v.hadm_id AND i.stay_id = v.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce 
    ON c.subject_id = ce.subject_id 
    AND c.hadm_id = ce.hadm_id
    AND ce.stay_id = i.stay_id
    AND ce.charttime >= i.intime 
    AND ce.charttime <= TIMESTAMP_ADD(i.intime, INTERVAL 1 DAY)
  GROUP BY c.subject_id, c.hadm_id
),

risk_scores AS (
  SELECT 
    c.*,
    COALESCE(v.composite_score, 0) AS composite_score,
    NTILE(4) OVER (ORDER BY COALESCE(v.composite_score, 0) DESC) AS quartile
  FROM cohort c
  LEFT JOIN vitals v ON c.subject_id = v.subject_id AND c.hadm_id = v.hadm_id
),

-- Rates over full cohort per quartile
rates AS (
  SELECT 
    quartile,
    -- 30-day mortality rate
    SUM(mortality_30d) * 1.0 / COUNT(*) AS mortality_rate,
    -- CV complication rate
    SUM(has_cv_comp) * 1.0 / COUNT(*) AS cv_comp_rate,
    -- Neurologic complication rate
    SUM(has_neuro_comp) * 1.0 / COUNT(*) AS neuro_comp_rate
  FROM risk_scores
  GROUP BY quartile

  UNION ALL

  -- All-quartile aggregate for rates
  SELECT 
    0 AS quartile,
    SUM(mortality_30d) * 1.0 / COUNT(*) AS mortality_rate,
    SUM(has_cv_comp) * 1.0 / COUNT(*) AS cv_comp_rate,
    SUM(has_neuro_comp) * 1.0 / COUNT(*) AS neuro_comp_rate
  FROM risk_scores
),

-- Median LOS for survivors only, per quartile
los_medians AS (
  SELECT 
    quartile,
    PERCENTILE_CONT(los_days, 0.5) AS median_los_survivors
  FROM risk_scores
  WHERE hospital_expire_flag = 0
  GROUP BY quartile

  UNION ALL

  -- Baseline all-quartile median LOS for survivors
  SELECT 
    0 AS quartile,
    PERCENTILE_CONT(los_days, 0.5) AS median_los_survivors
  FROM risk_scores
  WHERE hospital_expire_flag = 0
)

-- Join rates and LOS
SELECT 
  CASE WHEN r.quartile = 0 THEN 'Baseline (All)' ELSE 'Quartile ' || r.quartile END AS quartile_group,
  r.mortality_rate,
  r.cv_comp_rate,
  r.neuro_comp_rate,
  l.median_los_survivors
FROM rates r
LEFT JOIN los_medians l ON r.quartile = l.quartile
ORDER BY quartile;