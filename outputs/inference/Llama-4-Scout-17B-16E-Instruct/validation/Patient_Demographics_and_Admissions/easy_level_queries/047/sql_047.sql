WITH 
  -- Identify patients of interest (females, aged 82-92)
  patients_of_interest AS (
    SELECT subject_id, anchor_age, gender
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'F' AND anchor_age BETWEEN 82 AND 92
  ),

  -- Identify patients with AKI
  aki_patients AS (
    SELECT DISTINCT subject_id, hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_code LIKE '584%'  -- AKI ICD code
  ),

  -- First ICU stay for patients with AKI
  first_icu_stay AS (
    SELECT 
      i.subject_id,
      i.hadm_id,
      i.stay_id,
      i.intime,
      i.outtime,
      DATE_DIFF(i.outtime, i.intime, DAY) AS los_days
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays` i
    JOIN 
      patients_of_interest p ON i.subject_id = p.subject_id
    JOIN 
      aki_patients a ON i.hadm_id = a.hadm_id
    WHERE 
      i.intime IS NOT NULL AND i.outtime IS NOT NULL
  ),

  -- Identify first ICU LOS for each patient
  first_icu_los AS (
    SELECT 
      subject_id,
      MIN(los_days) AS first_icu_los_days
    FROM 
      first_icu_stay
    GROUP BY 
      subject_id
  )

-- Calculate 25th percentile of first ICU LOS
SELECT 
  APPROX_QUANTILES(first_icu_los_days, 100)[OFFSET(25)] AS percentile_25
FROM 
  first_icu_los;