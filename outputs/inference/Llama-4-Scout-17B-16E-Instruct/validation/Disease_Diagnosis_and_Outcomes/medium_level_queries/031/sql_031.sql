WITH 
  -- Identify patients of interest
  patients_of_interest AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.deathtime,
      ic.stay_id,
      ic.intime AS icu_intime,
      ic.outtime AS icu_outtime,
      ic.los,
      CASE 
        WHEN ic.los <= 7 THEN '≤7 days'
        ELSE '>7 days'
      END AS los_category
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_icu.icustays` ic 
        ON a.hadm_id = ic.hadm_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    WHERE 
      p.gender = 'F'
      AND p.anchor_age BETWEEN 53 AND 63
      AND a.admission_type IN ('sepsis', 'septic shock')
  ),

  -- Calculate in-hospital mortality for each category
  mortality_rates AS (
    SELECT 
      los_category,
      COUNT(CASE WHEN deathtime IS NOT NULL THEN hadm_id END) AS deaths,
      COUNT(hadm_id) AS total_patients,
      COUNT(CASE WHEN deathtime IS NOT NULL THEN hadm_id END) / COUNT(hadm_id) AS in_hospital_mortality_rate
    FROM 
      patients_of_interest
    GROUP BY 
      los_category
  )

-- Calculate differences
SELECT 
  m1.los_category AS group1,
  m2.los_category AS group2,
  m1.in_hospital_mortality_rate AS rate1,
  m2.in_hospital_mortality_rate AS rate2,
  ABS(m2.in_hospital_mortality_rate - m1.in_hospital_mortality_rate) AS absolute_difference,
  CASE 
    WHEN m1.in_hospital_mortality_rate = 0 THEN NULL 
    ELSE (m2.in_hospital_mortality_rate - m1.in_hospital_mortality_rate) / m1.in_hospital_mortality_rate * 100 
  END AS relative_difference
FROM 
  mortality_rates m1
CROSS JOIN 
  mortality_rates m2
WHERE 
  (m1.los_category = '≤7 days' AND m2.los_category = '>7 days')
  OR (m1.los_category = '>7 days' AND m2.los_category = '≤7 days');