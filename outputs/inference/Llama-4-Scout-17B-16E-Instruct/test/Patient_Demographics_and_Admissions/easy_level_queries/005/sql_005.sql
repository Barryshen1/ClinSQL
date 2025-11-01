WITH 
  -- Identify patients of interest
  patients_of_interest AS (
    SELECT 
      p.subject_id,
      p.anchor_age,
      p.gender,
      a.hadm_id
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON 
      p.subject_id = a.subject_id
    WHERE 
      p.gender = 'F'
      AND p.anchor_age BETWEEN 77 AND 87
  ),
  
  -- Identify dialysis patients (using ICD-9 and ICD-10 codes for simplicity)
  dialysis_patients AS (
    SELECT 
      subject_id,
      hadm_id
    FROM 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE 
      icd_code LIKE '%585%'  -- ICD-9 code for chronic kidney disease
      OR icd_code LIKE '%N18%'  -- ICD-10 code for chronic kidney disease
      OR icd_code LIKE '%V56%'  -- ICD-9 code for dialysis
      OR icd_code LIKE '%Z49%'  -- ICD-10 code for dialysis
  ),
  
  -- Calculate first ICU length of stay
  first_icu_stay_lengths AS (
    SELECT 
      poi.subject_id,
      i.stay_id,
      DATE_DIFF(i.outtime, i.intime, DAY) / 365.25 AS icu_length_of_stay
    FROM 
      patients_of_interest poi
    JOIN 
      dialysis_patients dp
    ON 
      poi.subject_id = dp.subject_id
      AND poi.hadm_id = dp.hadm_id
    JOIN 
      `physionet-data.mimiciv_3_1_icu.icustays` i
    ON 
      poi.hadm_id = i.hadm_id
    WHERE 
      i.intime = (
        SELECT 
          MIN(intime)
        FROM 
          `physionet-data.mimiciv_3_1_icu.icustays`
        WHERE 
          hadm_id = poi.hadm_id
      )
  )

-- Calculate percentiles and IQR of first ICU length of stay
SELECT 
  APPROX_QUANTILES(icu_length_of_stay, 0.25)[OFFSET(1)] AS q1,
  APPROX_QUANTILES(icu_length_of_stay, 0.5)[OFFSET(1)] AS median,
  APPROX_QUANTILES(icu_length_of_stay, 0.75)[OFFSET(1)] AS q3,
  APPROX_QUANTILES(icu_length_of_stay, 0.75)[OFFSET(1)] - 
  APPROX_QUANTILES(icu_length_of_stay, 0.25)[OFFSET(1)] AS iqr
FROM 
  first_icu_stay_lengths;