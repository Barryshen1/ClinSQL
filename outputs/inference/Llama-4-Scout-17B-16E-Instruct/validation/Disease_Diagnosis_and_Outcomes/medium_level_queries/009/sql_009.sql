WITH 
-- Define sepsis and septic shock
sepsis_patients AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    p.anchor_age,
    p.gender
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 53 AND 63
    AND a.hadm_id IN (
      SELECT 
        hadm_id
      FROM 
        `physionet-data.mimiciv_3_1_icu.icustays`
      WHERE 
        -- Assuming sepsis is identified by specific conditions within the ICU stay
        -- For simplicity, let's assume we have a flag or specific lab values
        -- Here we use a placeholder condition
        stay_id IN (
          SELECT 
            stay_id
          FROM 
            `physionet-data.mimiciv_3_1_icu.chartevents`
          WHERE 
            itemid IN (
              -- Placeholder itemids for sepsis indicators
              220050,  -- Example itemid
              220051   -- Example itemid
            )
        )
    )
    AND a.hadm_id NOT IN (
      -- Exclude septic shock, assuming it's identified by specific vasopressor use
      SELECT 
        hadm_id
      FROM 
        `physionet-data.mimiciv_3_1_icu.chartevents`
      WHERE 
        itemid IN (
          -- Placeholder itemid for vasopressors
          220070  -- Example itemid for vasopressors
        )
    )
),

icu_stays AS (
  SELECT 
    subject_id,
    hadm_id,
    stay_id,
    intime,
    outtime,
    los
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays`
),

-- Identify mechanical ventilation, vasopressors, and RRT
interventions AS (
  SELECT 
    subject_id,
    hadm_id,
    stay_id,
    charttime,
    itemid,
    value
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents`
  WHERE 
    itemid IN (
      -- Mechanical ventilation
      220050,
      -- Vasopressors
      220070,
      -- RRT
      220080
    )
),

-- Calculate in-hospital mortality and prevalence of interventions
results AS (
  SELECT 
    sp.hadm_id,
    sp.subject_id,
    CASE 
      WHEN sp.deathtime IS NOT NULL THEN 1
      ELSE 0
    END AS in_hospital_mortality,
    ii.stay_id,
    ii.charttime,
    ii.itemid
  FROM 
    sepsis_patients sp
  LEFT JOIN 
    icu_stays is_stay
  ON 
    sp.hadm_id = is_stay.hadm_id
  LEFT JOIN 
    interventions ii
  ON 
    sp.subject_id = ii.subject_id
    AND sp.hadm_id = ii.hadm_id
)

-- Final calculation
SELECT 
  CASE 
    WHEN is_stay.los < 8 THEN '<8'
    ELSE '≥8'
  END AS los_group,
  COUNT(DISTINCT CASE WHEN r.in_hospital_mortality = 1 THEN r.hadm_id END) / COUNT(DISTINCT r.hadm_id) AS mortality_rate,
  COUNT(DISTINCT CASE WHEN r.itemid = 220050 THEN r.hadm_id END) / COUNT(DISTINCT r.hadm_id) AS mech_vent_rate,
  COUNT(DISTINCT CASE WHEN r.itemid = 220070 THEN r.hadm_id END) / COUNT(DISTINCT r.hadm_id) AS vasopressor_rate,
  COUNT(DISTINCT CASE WHEN r.itemid = 220080 THEN r.hadm_id END) / COUNT(DISTINCT r.hadm_id) AS rrt_rate
FROM 
  results r
JOIN 
  icu_stays is_stay
ON 
  r.hadm_id = is_stay.hadm_id
GROUP BY 
  1;