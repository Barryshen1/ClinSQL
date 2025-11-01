WITH 
  -- Select relevant patients
  patients_icu AS (
    SELECT 
      p.subject_id,
      p.anchor_age,
      p.gender,
      ic.stay_id,
      ic.intime,
      ic.outtime,
      a.hadm_id,
      a.deathtime
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays` ic
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a 
        ON ic.subject_id = a.subject_id AND ic.hadm_id = a.hadm_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON ic.subject_id = p.subject_id
    WHERE 
      p.gender = 'M' AND p.anchor_age BETWEEN 78 AND 88
  ),
  
  -- Calculate ICU LOS
  icu_los AS (
    SELECT 
      subject_id,
      hadm_id,
      stay_id,
      TIMESTAMP_DIFF(outtime, intime, DAY) AS icu_los_days
    FROM 
      patients_icu
  ),
  
  -- Calculate mortality
  mortality AS (
    SELECT 
      subject_id,
      hadm_id,
      CASE 
        WHEN deathtime IS NOT NULL THEN 1 
        ELSE 0 
      END AS died_in_hospital
    FROM 
      patients_icu
  )

-- Final calculation
SELECT 
  APPROX_QUANTILES(icu_los_days, 0.25)[OFFSET(0)] AS los_25th_percentile,
  APPROX_QUANTILES(icu_los_days, 0.5)[OFFSET(0)] AS los_median,
  APPROX_QUANTILES(icu_los_days, 0.75)[OFFSET(0)] AS los_75th_percentile,
  AVG(died_in_hospital) AS mortality_rate
FROM 
  icu_los
  JOIN mortality USING (subject_id, hadm_id);