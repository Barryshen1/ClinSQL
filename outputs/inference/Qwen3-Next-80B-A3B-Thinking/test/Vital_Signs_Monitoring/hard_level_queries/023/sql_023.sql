WITH patients_icu AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    i.stay_id,
    i.los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON p.subject_id = i.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 55 AND 65
),

hfnc_patients AS (
  SELECT 
    i.stay_id,
    CASE WHEN COUNT(di.itemid) > 0 THEN 1 ELSE 0 END AS has_hfnc
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie 
    ON i.stay_id = ie.stay_id 
    AND ie.starttime BETWEEN i.intime AND i.intime + INTERVAL 24 HOUR
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di 
    ON ie.itemid = di.itemid 
    AND (di.label LIKE '%HFNC%' OR di.label LIKE '%High Flow Nasal Cannula%')
  GROUP BY i.stay_id
),

tachycardia AS (
  SELECT 
    c.stay_id,
    SUM(CASE WHEN c.valuenum > 100 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS tachycardia_proportion
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  WHERE c.itemid = 220045  -- Heart Rate
    AND c.valuenum IS NOT NULL
  GROUP BY c.stay_id
),

hypotension AS (
  SELECT 
    c.stay_id,
    SUM(CASE WHEN c.valuenum < 90 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS hypotension_proportion
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  WHERE c.itemid = 220050  -- Systolic BP
    AND c.valuenum IS NOT NULL
  GROUP BY c.stay_id
),

map AS (
  SELECT 
    c.stay_id,
    AVG(c.valuenum) AS avg_map
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  WHERE c.itemid = 220052  -- Mean Arterial Pressure
    AND c.valuenum IS NOT NULL
  GROUP BY c.stay_id
)

SELECT 
  CASE WHEN hfnc.has_hfnc = 1 THEN 'HFNC' ELSE 'Control' END AS group_type,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.los) AS median_los,
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY p.los) AS p25_los,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY p.los) AS p75_los,
  PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY p.los) AS p95_los,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY t.tachycardia_proportion) AS median_tachycardia,
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY t.tachycardia_proportion) AS p25_tachycardia,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY t.tachycardia_proportion) AS p75_tachycardia,
  PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY t.tachycardia_proportion) AS p95_tachycardia,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY h.hypotension_proportion) AS median_hypotension,
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY h.hypotension_proportion) AS p25_hypotension,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY h.hypotension_proportion) AS p75_hypotension,
  PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY h.hypotension_proportion) AS p95_hypotension,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY m.avg_map) AS median_map,
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY m.avg_map) AS p25_map,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY m.avg_map) AS p75_map,
  PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY m.avg_map) AS p95_map,
  AVG(p.hospital_expire_flag) AS mortality_rate
FROM patients_icu p
LEFT JOIN hfnc_patients hfnc ON p.stay_id = hfnc.stay_id
LEFT JOIN tachycardia t ON p.stay_id = t.stay_id
LEFT JOIN hypotension h ON p.stay_id = h.stay_id
LEFT JOIN map m ON p.stay_id = m.stay_id
GROUP BY group_type;