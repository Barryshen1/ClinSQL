WITH 
  -- Identify stroke patients
  stroke_patients AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      ic.icd_code AS stroke_icd_code
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` ic
    ON 
      a.subject_id = ic.subject_id AND a.hadm_id = ic.hadm_id
    WHERE 
      ic.icd_code LIKE 'I63%' OR ic.icd_code LIKE 'I64%'  -- Stroke ICD codes
  ),

  -- First ICU admission for stroke patients
  first_icu_admission AS (
    SELECT 
      i.subject_id,
      i.hadm_id,
      i.stay_id,
      i.intime,
      i.outtime,
      EXTRACT(DAY FROM i.outtime - i.intime) AS icu_los_days
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays` i
    JOIN 
      stroke_patients sp
    ON 
      i.subject_id = sp.subject_id AND i.hadm_id = sp.hadm_id
    WHERE 
      i.intime IS NOT NULL AND i.outtime IS NOT NULL
  ),

  -- Filter male patients aged 46-56
  target_patients AS (
    SELECT 
      faa.subject_id,
      faa.hadm_id,
      faa.stay_id,
      faa.icu_los_days
    FROM 
      first_icu_admission faa
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    ON 
      faa.subject_id = p.subject_id
    WHERE 
      p.gender = 'M' AND 
      p.anchor_age BETWEEN 46 AND 56
  )

SELECT 
  APPROX_QUANTILES(icu_los_days, 100)[75] - 
  APPROX_QUANTILES(icu_los_days, 100)[25] AS iqr_icu_los_days
FROM 
  target_patients;