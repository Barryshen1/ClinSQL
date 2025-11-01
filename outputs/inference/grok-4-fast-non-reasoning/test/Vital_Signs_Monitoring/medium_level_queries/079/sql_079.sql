WITH eligible_stays AS (
  -- Filter to male patients aged 40-50 with first ICU stay
  SELECT 
    p.subject_id,
    i.stay_id,
    i.hadm_id,
    i.intime,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY i.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON p.subject_id = i.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 40 AND 50
    AND rn = 1  -- Ensure only first ICU stay per patient
),

systolic_bp AS (
  -- Extract SBP measurements in first 48 hours
  SELECT 
    es.stay_id,
    es.hadm_id,
    c.valuenum AS sbp
  FROM eligible_stays es
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON es.subject_id = c.subject_id
    AND es.hadm_id = c.hadm_id
    AND es.stay_id = c.stay_id
  WHERE c.itemid = 220045  -- Arterial systolic blood pressure
    AND c.valuenum IS NOT NULL
    AND c.valuenum > 0
    AND c.charttime >= es.intime
    AND c.charttime < TIMESTAMP_ADD(es.intime, INTERVAL 48 HOUR)
),

stay_sbp AS (
  -- Compute per-stay mean SBP
  SELECT 
    stay_id,
    hadm_id,
    AVG(sbp) AS avg_sbp
  FROM systolic_bp
  GROUP BY stay_id, hadm_id
),

mi_admissions AS (
  -- Identify admissions with acute MI (ICD-10 I21.*)
  SELECT DISTINCT
    d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE d.icd_version = 'ICD-10'
    AND d.icd_code LIKE 'I21%'
),

categorized_stays AS (
  -- Categorize stays and flag MI
  SELECT 
    s.stay_id,
    s.hadm_id,
    s.avg_sbp,
    CASE 
      WHEN s.avg_sbp < 140 THEN '<140'
      WHEN s.avg_sbp >= 140 AND s.avg_sbp < 160 THEN '140-159'
      WHEN s.avg_sbp >= 160 THEN '>=160'
      ELSE NULL
    END AS sbp_category,
    CASE WHEN m.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_mi
  FROM stay_sbp s
  LEFT JOIN mi_admissions m
    ON s.hadm_id = m.hadm_id
)

-- Compute percentages
SELECT 
  sbp_category,
  ROUND((COUNT(*) * 100.0 / (SELECT COUNT(*) FROM categorized_stays)), 2) AS percent_of_stays,
  ROUND((SUM(has_mi) * 100.0 / COUNT(*)), 2) AS mi_rate_percent
FROM categorized_stays
WHERE sbp_category IS NOT NULL
GROUP BY sbp_category
ORDER BY 
  CASE sbp_category
    WHEN '<140' THEN 1
    WHEN '140-159' THEN 2
    WHEN '>=160' THEN 3
  END;