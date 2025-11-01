WITH 
  -- Filter patients and admissions
  patients_admissions AS (
    SELECT 
      a.hadm_id,
      a.admittime,
      a.dischtime,
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
      AND p.anchor_age BETWEEN 40 AND 50
  ),

  -- Filter primary diagnosis of ischemic heart disease/ACS
  primary_diagnosis AS (
    SELECT 
      hadm_id
    FROM 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE 
      icd_code IN ('I24', 'I25')
      AND seq_num = 1  -- Primary diagnosis
  ),

  -- Calculate LOS
  los_calculation AS (
    SELECT 
      TIMESTAMP_DIFF(pa.dischtime, pa.admittime, DAY) AS los
    FROM 
      patients_admissions pa
    JOIN 
      primary_diagnosis pd
    ON 
      pa.hadm_id = pd.hadm_id
  )

SELECT 
  APPROX_QUANTILES(los, 0.25)[OFFSET(0)] AS los_25th_percentile
FROM 
  los_calculation;