WITH cohort AS (
  SELECT 
    p.subject_id,
    ie.stay_id,
    p.anchor_age,
    ie.intime,
    ie.outtime,
    a.deathtime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` ie ON p.subject_id = ie.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON ie.hadm_id = a.hadm_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 60 AND 70
    -- Replace 'Hypothetical_ICD_Code_for_Mixed_Shock' with actual ICD codes for mixed shock
    AND ie.stay_id IN (
      SELECT stay_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE icd_code = 'Hypothetical_ICD_Code_for_Mixed_Shock'
    )
),
vital_signs AS (
  SELECT 
    c.stay_id,
    ce.charttime,
    c.intime,
    ce.valuenum AS map_value,
    CASE WHEN ce.valuenum < 65 THEN 1 ELSE 0 END AS hypotension
  FROM 
    cohort c
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce ON c.stay_id = ce.stay_id
  WHERE 
    ce.itemid = 220052  
    AND ce.charttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 48 HOUR)
),
heart_rate AS (
  SELECT 
    stay_id,
    charttime,
    valuenum AS heart_rate_value
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` 
  WHERE 
    itemid = 220045
),
aligned_vitals AS (
  SELECT 
    vs.stay_id,
    vs.charttime,
    vs.map_value,
    vs.hypotension,
    hr.heart_rate_value
  FROM 
    vital_signs vs
  LEFT JOIN 
    heart_rate hr ON vs.stay_id = hr.stay_id AND vs.charttime = hr.charttime
),
instability_score AS (
  SELECT 
    stay_id,
    PERCENTILE_CONT(ABS(map_value - 65), 0.95) OVER (PARTITION BY stay_id) AS map_95th_percentile,
    PERCENTILE_CONT(ABS(heart_rate_value - 100), 0.95) OVER (PARTITION BY stay_id) AS hr_95th_percentile
  FROM 
    aligned_vitals
),
icu_outcomes AS (
  SELECT 
    c.stay_id,
    TIMESTAMP_DIFF(c.outtime, c.intime, HOUR) AS icu_los_hours,
    CASE WHEN c.deathtime IS NOT NULL AND c.deathtime BETWEEN c.intime AND c.outtime THEN 1 ELSE 0 END AS icu_mortality
  FROM 
    cohort c
),
avg_hypotension AS (
  SELECT 
    stay_id, 
    AVG(hypotension) AS avg_hypotension
  FROM 
    vital_signs
  GROUP BY 
    stay_id
)
SELECT 
  PERCENTILE_CONT(map_95th_percentile, 0.95) OVER () AS cohort_95th_percentile_instability,
  AVG(CASE WHEN map_95th_percentile > (PERCENTILE_CONT(map_95th_percentile, 0.9) OVER ()) THEN ah.avg_hypotension ELSE NULL END) AS top_decile_hypotension,
  AVG(ah.avg_hypotension) AS cohort_hypotension,
  AVG(CASE WHEN map_95th_percentile > (PERCENTILE_CONT(map_95th_percentile, 0.9) OVER ()) THEN iscore.hr_95th_percentile ELSE NULL END) AS top_decile_hr_instability,
  AVG(iscore.hr_95th_percentile) AS cohort_hr_instability,
  AVG(CASE WHEN map_95th_percentile > (PERCENTILE_CONT(map_95th_percentile, 0.9) OVER ()) THEN iou.icu_los_hours ELSE NULL END) AS top_decile_icu_los,
  AVG(iou.icu_los_hours) AS cohort_icu_los,
  AVG(CASE WHEN map_95th_percentile > (PERCENTILE_CONT(map_95th_percentile, 0.9) OVER ()) THEN iou.icu_mortality ELSE NULL END) AS top_decile_icu_mortality,
  AVG(iou.icu_mortality) AS cohort_icu_mortality
FROM 
  instability_score iscore
JOIN 
  icu_outcomes iou ON iscore.stay_id = iou.stay_id
JOIN 
  avg_hypotension ah ON iscore.stay_id = ah.stay_id;