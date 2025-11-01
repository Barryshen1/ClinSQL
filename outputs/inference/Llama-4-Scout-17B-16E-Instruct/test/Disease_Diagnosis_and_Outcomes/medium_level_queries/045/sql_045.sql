WITH 
  -- Select target patients
  target_patients AS (
    SELECT 
      a.subject_id, 
      a.hadm_id, 
      p.anchor_age, 
      p.gender
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    ON 
      a.subject_id = p.subject_id
    WHERE 
      p.gender = 'F' 
      AND p.anchor_age BETWEEN 79 AND 89
  ),

  -- Identify pneumonia types
  pneumonia_patients AS (
    SELECT 
      tp.subject_id, 
      tp.hadm_id
    FROM 
      target_patients tp
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON 
      tp.hadm_id = d.hadm_id
    WHERE 
      d.icd_code LIKE '481%'  -- Pneumonia, organism not specified
      OR d.icd_code LIKE '482%'  -- Pneumonia due to bacteria
      OR d.icd_code = '486'     -- Pneumonia, unspecified organism
      OR d.icd_code LIKE '507%'  -- Pneumonitis due to solids and liquids (aspiration pneumonia)
  ),

  -- Calculate LOS and mortality
  los_mortality AS (
    SELECT 
      pp.hadm_id, 
      TIMESTAMP_DIFF(COALESCE(a.dischtime, a.deathtime), a.admittime, DAY) AS los,
      a.hospital_expire_flag
    FROM 
      pneumonia_patients pp
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON 
      pp.hadm_id = a.hadm_id
  ),

  -- ICU admissions on day 1
  icu_day1 AS (
    SELECT 
      hadm_id, 
      COUNT(stay_id) AS icu_admits
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays`
    GROUP BY 
      hadm_id
  ),

  -- Mech vent, vasopressor, RRT
  interventions AS (
    SELECT 
      ce.subject_id, 
      ce.hadm_id, 
      ce.stay_id,
      MAX(CASE WHEN ce.itemid = 220050 AND ce.value = 'Yes' THEN 1 ELSE 0 END) AS mech_vent,
      MAX(CASE WHEN ce.itemid = 221050 AND ce.value = 'Yes' THEN 1 ELSE 0 END) AS vasopressor,
      MAX(CASE WHEN ce.itemid = 221170 AND ce.value = 'Yes' THEN 1 ELSE 0 END) AS rrt
    FROM 
      `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN 
      `physionet-data.mimiciv_3_1_icu.icustays` is_stay
    ON 
      ce.hadm_id = is_stay.hadm_id AND ce.stay_id = is_stay.stay_id
    WHERE 
      ce.charttime BETWEEN is_stay.intime AND is_stay.intime + INTERVAL 1 DAY
    GROUP BY 
      ce.subject_id, 
      ce.hadm_id, 
      ce.stay_id
  )

SELECT 
  CASE 
    WHEN lm.los <= 7 THEN '≤7'
    ELSE '>7'
  END AS los_category,
  AVG(lm.hospital_expire_flag) AS mortality_rate,
  COUNT(DISTINCT lm.hadm_id) AS total_patients,
  SUM(CASE WHEN id1.icu_admits > 0 THEN 1 ELSE 0 END) AS day1_icu_admits,
  SUM(CASE WHEN i.mech_vent = 1 THEN 1 ELSE 0 END) AS mech_vent,
  SUM(CASE WHEN i.vasopressor = 1 THEN 1 ELSE 0 END) AS vasopressor,
  SUM(CASE WHEN i.rrt = 1 THEN 1 ELSE 0 END) AS rrt
FROM 
  los_mortality lm
  LEFT JOIN icu_day1 id1 ON lm.hadm_id = id1.hadm_id
  LEFT JOIN interventions i ON lm.hadm_id = i.hadm_id
GROUP BY 
  los_category;