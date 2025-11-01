WITH 
  -- Identify RRT patients
  rrt_patients AS (
    SELECT DISTINCT 
      i.subject_id, 
      i.hadm_id, 
      i.stay_id
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays` i
    JOIN 
      `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON 
      i.subject_id = c.subject_id 
      AND i.hadm_id = c.hadm_id 
      AND i.stay_id = c.stay_id
    WHERE 
      c.itemid IN (
        220050,  -- Arterial Line Blood Pressure
        220179   -- Heart Rate
      )
      AND c.charttime BETWEEN i.intime AND i.outtime
  ),

  -- Filter patients of interest
  patients_of_interest AS (
    SELECT 
      a.subject_id, 
      a.hadm_id
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    ON 
      a.subject_id = p.subject_id
    WHERE 
      p.gender = 'F'
      AND p.anchor_age BETWEEN 58 AND 68
  ),

  -- Calculate vital instability index
  vital_instability AS (
    SELECT 
      i.stay_id,
      i.subject_id,
      i.hadm_id,
      TIMESTAMP_DIFF(c.charttime, i.intime, HOUR) AS hours_in_icu,
      CASE 
        WHEN c.itemid = 220050 AND c.valuenum < 65 THEN 1
        ELSE 0
      END AS hypotensive_hours,
      CASE 
        WHEN c.itemid = 220179 AND c.valuenum > 100 THEN 1
        ELSE 0
      END AS tachycardic_hours
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays` i
    JOIN 
      `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON 
      i.subject_id = c.subject_id 
      AND i.hadm_id = c.hadm_id 
      AND i.stay_id = c.stay_id
    WHERE 
      c.charttime BETWEEN i.intime AND i.outtime
      AND c.itemid IN (220050, 220179)
  ),

  -- Aggregate data
  aggregated_data AS (
    SELECT 
      stay_id,
      subject_id,
      hadm_id,
      SUM(hypotensive_hours) AS total_hypotensive_hours,
      SUM(tachycardic_hours) AS total_tachycardic_hours,
      COUNT(hours_in_icu) AS total_hours_in_icu
    FROM 
      vital_instability
    GROUP BY 
      stay_id, subject_id, hadm_id
  )

-- Final query
SELECT 
  APPROX_QUANTILES(total_hypotensive_hours + total_tachycardic_hours, 100)[OFFSET(25)] AS p25_vital_instability,
  APPROX_QUANTILES(total_hypotensive_hours + total_tachycardic_hours, 100)[OFFSET(50)] AS p50_vital_instability,
  APPROX_QUANTILES(total_hypotensive_hours + total_tachycardic_hours, 100)[OFFSET(75)] AS p75_vital_instability,
  APPROX_QUANTILES(total_hypotensive_hours + total_tachycardic_hours, 100)[OFFSET(90)] AS p90_vital_instability,
  APPROX_QUANTILES(total_hypotensive_hours + total_tachycardic_hours, 100)[OFFSET(75)] - 
  APPROX_QUANTILES(total_hypotensive_hours + total_tachycardic_hours, 100)[OFFSET(25)] AS iqr_hypotensive_tachycardic_hours,
  AVG(total_hours_in_icu) AS avg_icu_los,
  COUNT(*) AS num_patients
FROM 
  aggregated_data
  JOIN patients_of_interest poi ON aggregated_data.subject_id = poi.subject_id AND aggregated_data.hadm_id = poi.hadm_id
  JOIN rrt_patients rrt ON aggregated_data.stay_id = rrt.stay_id AND aggregated_data.subject_id = rrt.subject_id AND aggregated_data.hadm_id = rrt.hadm_id;