WITH patient_max_hr AS (
  SELECT 
    p.subject_id,
    MAX(ce.valuenum) AS max_hr
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    i.subject_id = p.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON 
    ce.subject_id = i.subject_id 
    AND ce.hadm_id = i.hadm_id 
    AND ce.stay_id = i.stay_id
    AND ce.itemid = 220045  -- Heart Rate
    AND ce.valuenum IS NOT NULL
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 55 AND 65
    AND EXTRACT(YEAR FROM i.intime) - p.anchor_year >= 18  -- Ensure adult age
    AND ce.charttime BETWEEN i.intime AND i.outtime
  GROUP BY 
    p.subject_id
  HAVING 
    max_hr IS NOT NULL
)
SELECT 
  PERCENTILE_CONT(0.75, 0) OVER() - PERCENTILE_CONT(0.25, 0) OVER() AS iqr_max_hr
FROM 
  patient_max_hr;