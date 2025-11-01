WITH 
  -- Identify first hospital admission for each patient
  first_admission AS (
    SELECT subject_id, MIN(hadm_id) AS first_hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions`
    GROUP BY subject_id
  ),
  
  -- Identify first ICU stay for each patient in their first admission
  first_icu_stay AS (
    SELECT i.subject_id, i.hadm_id, i.stay_id,
           TIMESTAMP_DIFF(i.outtime, i.intime, DAY) AS icu_los,
           ROW_NUMBER() OVER (PARTITION BY i.subject_id, i.hadm_id ORDER BY i.intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    JOIN first_admission fa ON i.subject_id = fa.subject_id AND i.hadm_id = fa.first_hadm_id
  ),
  
  -- Filter first ICU stay
  filtered_icu_stay AS (
    SELECT subject_id, hadm_id, stay_id, icu_los
    FROM first_icu_stay
    WHERE rn = 1
  ),
  
  -- Identify female patients aged 50-60 on anticoagulants
  eligible_patients AS (
    SELECT DISTINCT p.subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr ON p.subject_id = pr.subject_id
    WHERE p.gender = 'F' AND p.anchor_age BETWEEN 50 AND 60
    AND LOWER(pr.drug) LIKE '%anticoagulant%'  
  )

SELECT 
  APPROX_QUANTILES(icu_los, 0.5) AS median_icu_los
FROM 
  filtered_icu_stay ficu
  JOIN eligible_patients ep ON ficu.subject_id = ep.subject_id;