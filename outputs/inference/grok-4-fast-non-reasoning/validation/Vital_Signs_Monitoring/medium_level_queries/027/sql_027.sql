WITH heart_rates AS (
  SELECT 
    c.stay_id,
    AVG(c.valuenum) AS avg_hr
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    i.subject_id = p.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  ON 
    i.subject_id = c.subject_id 
    AND i.hadm_id = c.hadm_id 
    AND i.stay_id = c.stay_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 90
    AND i.first_careunit IS NOT NULL
    AND i.los > 0
    AND c.itemid IN (
      SELECT itemid 
      FROM `physionet-data.mimiciv_3_1_icu.d_items` 
      WHERE label = 'Heart Rate' AND category = 'Routine Vital Signs'
    )
    AND c.charttime BETWEEN i.intime AND i.outtime
    AND c.valuenum IS NOT NULL 
    AND c.valuenum > 0
  GROUP BY 
    c.stay_id
  HAVING 
    COUNT(c.valuenum) >= 3  -- At least 3 measurements for reliable average
),
percentile_calc AS (
  SELECT 
    stay_id,
    avg_hr,
    PERCENT_RANK() OVER (ORDER BY avg_hr) AS percentile_rank
  FROM 
    heart_rates
)
SELECT 
  ROUND(
    (SELECT percentile_rank * 100 
     FROM percentile_calc 
     WHERE avg_hr >= 110 
     ORDER BY avg_hr 
     LIMIT 1),  -- Finds the smallest rank where avg_hr >= 110 (conservative estimate)
    2
  ) AS percentile_for_110_bpm
FROM 
  (SELECT 1) AS dummy;  -- Ensures single-row output;