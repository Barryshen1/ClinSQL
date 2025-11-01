WITH 
  -- Identify CABG procedure
  cabg_procedures AS (
    SELECT 
      subject_id, 
      hadm_id, 
      icd_code
    FROM 
      `physionet-data.mimiciv_3_1_hosp.procedures_icd`
    WHERE 
      icd_code IN ('36.02', '36.1', '36.2', '36.3', '36.01')  -- CABG ICD codes
  ),

  -- First CABG admission for each patient
  first_cabg_admission AS (
    SELECT 
      a.subject_id, 
      a.hadm_id, 
      ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS rn
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      cabg_procedures cp ON a.hadm_id = cp.hadm_id
  ),

  -- ICU stay details for first CABG admission
  icu_stay_details AS (
    SELECT 
      ic.stay_id, 
      ic.subject_id, 
      ic.hadm_id, 
      ic.intime, 
      ic.outtime,
      TIMESTAMP_DIFF(ic.outtime, ic.intime, DAY) AS icu_los
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays` ic
    JOIN 
      first_cabg_admission fca ON ic.hadm_id = fca.hadm_id
    WHERE 
      fca.rn = 1
  )

-- Calculate mean ICU LOS for males aged 74-84
SELECT 
  AVG(icu_los) AS mean_icu_los
FROM 
  icu_stay_details
JOIN 
  `physionet-data.mimiciv_3_1_hosp.patients` p ON icu_stay_details.subject_id = p.subject_id
WHERE 
  p.gender = 'M' 
  AND p.anchor_age BETWEEN 74 AND 84;