WITH icu_stays AS (
  -- Filter female ICU stays for ages 48-58
  SELECT 
    p.subject_id,
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
    AND i.first_careunit IN ('CCU', 'CSRU', 'MICU', 'SICU', 'Neuro ICU', 'NICU', 'Cardiac ICU')
    AND i.los >= 1  -- At least 1 day for AKI assessment
),
hr_data AS (
  -- HR measurements in first 48h per stay
  SELECT 
    s.stay_id,
    AVG(ce.valuenum) AS avg_hr
  FROM icu_stays s
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON s.subject_id = ce.subject_id
    AND s.hadm_id = ce.hadm_id
    AND s.stay_id = ce.stay_id
  WHERE ce.itemid = 220045  -- Heart rate
    AND ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN s.intime AND DATETIME_ADD(s.intime, INTERVAL 48 HOUR)
  GROUP BY s.stay_id
  HAVING avg_hr IS NOT NULL  -- Exclude stays with no HR data
),
scr_data AS (
  -- Serum creatinine for AKI assessment
  SELECT 
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum AS scr
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN icu_stays s
    ON le.subject_id = s.subject_id
    AND le.hadm_id = s.hadm_id
  WHERE le.itemid = 50912  -- Serum creatinine
    AND le.valuenum IS NOT NULL
    AND le.valueuom = 'mg/dL'  -- Standard unit
),
stay_metrics AS (
  -- Per-stay HR category and AKI flag
  SELECT 
    h.stay_id,
    CASE 
      WHEN h.avg_hr < 60 THEN '<60'
      WHEN h.avg_hr >= 60 AND h.avg_hr <= 99 THEN '60-99'
      WHEN h.avg_hr >= 100 AND h.avg_hr <= 119 THEN '100-119'
      WHEN h.avg_hr >= 120 THEN '>=120'
    END AS hr_category,
    -- Baseline SCr: min in [-48h, 0h] or 0.7 if missing
    COALESCE(
      (SELECT MIN(d.scr) 
       FROM scr_data d 
       WHERE d.subject_id = s.subject_id 
         AND d.hadm_id = s.hadm_id
         AND d.charttime BETWEEN DATETIME_SUB(s.intime, INTERVAL 48 HOUR) AND s.intime),
      0.7
    ) AS baseline_scr,
    -- Max SCr in [0h, 48h]
    (SELECT MAX(d.scr) 
     FROM scr_data d 
     WHERE d.subject_id = s.subject_id 
       AND d.hadm_id = s.hadm_id
       AND d.charttime BETWEEN s.intime AND DATETIME_ADD(s.intime, INTERVAL 48 HOUR)
    ) AS max_scr_48h
  FROM icu_stays s
  INNER JOIN hr_data h ON s.stay_id = h.stay_id
),
final_stats AS (
  SELECT 
    hr_category,
    COUNT(*) AS num_stays,
    COUNT(*) * 100.0 / COUNT(*) OVER() AS pct_distribution,
    AVG(CASE 
      WHEN max_scr_48h >= 1.5 * baseline_scr THEN 1.0 
      ELSE 0.0 
    END) * 100.0 AS aki_rate_pct
  FROM stay_metrics
  WHERE max_scr_48h IS NOT NULL  -- Exclude if no SCr in 48h (can't assess AKI)
  GROUP BY hr_category
)
SELECT 
  hr_category,
  ROUND(pct_distribution, 1) AS percent_distribution,
  ROUND(aki_rate_pct, 1) AS aki_rate_percent
FROM final_stats
ORDER BY 
  CASE hr_category
    WHEN '<60' THEN 1
    WHEN '60-99' THEN 2
    WHEN '100-119' THEN 3
    WHEN '>=120' THEN 4
  END;