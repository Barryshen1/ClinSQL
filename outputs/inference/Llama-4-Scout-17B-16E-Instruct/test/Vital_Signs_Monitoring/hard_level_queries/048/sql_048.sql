WITH 
  -- Define invasive mechanical ventilation
  vent_patients AS (
    SELECT 
      i.subject_id, 
      i.hadm_id, 
      i.stay_id
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays` i
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON i.subject_id = p.subject_id
    WHERE 
      p.gender = 'F' 
      AND p.anchor_age BETWEEN 75 AND 85
      AND i.stay_id IN (
        SELECT 
          stay_id 
        FROM 
          `physionet-data.mimiciv_3_1_icu.chartevents` 
        WHERE 
          itemid IN (
            SELECT 
              itemid 
            FROM 
              `physionet-data.mimiciv_3_1_icu.d_items` 
            WHERE 
              label IN ('Ventilation Mode', 'Ventilator Type')
          ) 
          AND value LIKE '%Invasive%'
      )
  ),

  -- Calculate vital signs instability
  vital_signs AS (
    SELECT 
      vs.subject_id, 
      vs.hadm_id, 
      vs.stay_id,
      -- Example instability score components
      SUM(CASE 
        WHEN ve.valueuom = 'bpm' AND ve.valuenum > 120 THEN 1 
        ELSE 0 
      END) AS tachycardia,
      SUM(CASE 
        WHEN ve.valueuom = 'mmHg' AND ve.valuenum < 90 THEN 1 
        ELSE 0 
      END) AS hypotension
    FROM 
      vent_patients vs
    JOIN 
      `physionet-data.mimiciv_3_1_icu.chartevents` ve 
    ON vs.stay_id = ve.stay_id
    WHERE 
      ve.itemid IN (
        SELECT 
          itemid 
        FROM 
          `physionet-data.mimiciv_3_1_icu.d_items` 
        WHERE 
          label IN ('Heart Rate', 'Systolic Blood Pressure')
      )
    GROUP BY 
      vs.subject_id, 
      vs.hadm_id, 
      vs.stay_id
  ),

  -- Calculate ICU LOS and mortality
  icu_outcomes AS (
    SELECT 
      subject_id, 
      hadm_id, 
      stay_id,
      TIMESTAMP_DIFF(outtime, intime, DAY) AS icu_los,
      CASE 
        WHEN last_careunit = 'ICU' AND outtime IS NULL THEN 1 
        ELSE 0 
      END AS icu_mortality
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays`
  )

-- Calculate 90th percentile of instability score and top 25% of patients
SELECT 
  APPROX_QUANTILES(
    -- Example instability score calculation
    COALESCE(tachycardia, 0) + COALESCE(hypotension, 0), 
    0.9
  )[OFFSET(1)] AS percentile_90,
  APPROX_QUANTILES(
    -- Example outcomes
    io.icu_los, 
    0.75
  )[OFFSET(1)] AS top_25_percent_icu_los,
  AVG(io.icu_mortality) AS avg_mortality
FROM 
  vital_signs vs
JOIN 
  icu_outcomes io 
ON vs.subject_id = io.subject_id AND vs.hadm_id = io.hadm_id AND vs.stay_id = io.stay_id;