WITH 
  -- Patient demographics and ICU stay
  patient_stay AS (
    SELECT 
      p.subject_id, 
      p.gender, 
      p.anchor_age, 
      icu_stay.stay_id, 
      icu_stay.intime, 
      icu_stay.outtime
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN 
      `physionet-data.mimiciv_3_1_icu.icustays` icu_stay
        ON p.subject_id = icu_stay.subject_id
    WHERE 
      p.gender = 'F' AND 
      p.anchor_age BETWEEN 59 AND 69
  ),
  
  -- Shock diagnosis
  shock_diagnosis AS (
    SELECT 
      subject_id, 
      hadm_id
    FROM 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE 
      icd_code IN ('785.52', '785.51', 'R57.9', 'R57.1', 'R57.0', '998.0')
  ),
  
  -- Join patient stay with shock diagnosis
  patient_shock AS (
    SELECT 
      ps.subject_id, 
      ps.stay_id, 
      CASE 
        WHEN sd.hadm_id IS NOT NULL THEN 1 
        ELSE 0 
      END AS has_shock
    FROM 
      patient_stay ps
    LEFT JOIN 
      shock_diagnosis sd 
        ON ps.subject_id = sd.subject_id
  ),
  
  -- Calculate ICU LOS
  icu_los AS (
    SELECT 
      subject_id, 
      stay_id, 
      TIMESTAMPDIFF(HOUR, intime, outtime) AS los_hours
    FROM 
      patient_stay
  ),
  
  -- Mortality
  mortality AS (
    SELECT 
      subject_id, 
      dod
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients`
  ),
  
  -- Hypotension and Tachycardia Burden
  vital_signs AS (
    SELECT 
      subject_id, 
      stay_id, 
      charttime, 
      valueuom, 
      valuenum, 
      itemid
    FROM 
      `physionet-data.mimiciv_3_1_icu.chartevents`
    WHERE 
      itemid IN (220050, 220179)  -- MAP and Heart Rate
  )

SELECT 
  ps.has_shock,
  AVG(il.los_hours) AS mean_icu_los,
  PERCENTILE_CONT(0.25)(il.los_hours) AS p25_icu_los,
  PERCENTILE_CONT(0.5)(il.los_hours) AS p50_icu_los,
  PERCENTILE_CONT(0.75)(il.los_hours) AS p75_icu_los
FROM 
  patient_shock ps
JOIN 
  icu_los il 
    ON ps.subject_id = il.subject_id AND ps.stay_id = il.stay_id
GROUP BY 
  ps.has_shock;