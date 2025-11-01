WITH 
  -- Define patients of interest
  patients_of_interest AS (
    SELECT 
      a.subject_id, 
      a.hadm_id,
      p.anchor_age,
      p.gender,
      p.dod,
      a.admittime,
      a.dischtime,
      a.deathtime
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    ON 
      a.subject_id = p.subject_id
    WHERE 
      p.anchor_age BETWEEN 39 AND 49
      AND p.gender = 'F'
  ),
  
  -- Identify patients with T2DM and heart failure
  t2dm_heart_failure AS (
    SELECT 
      subject_id, 
      hadm_id
    FROM 
      patients_of_interest
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    ON 
      patients_of_interest.hadm_id = diagnoses_icd.hadm_id
    WHERE 
      diagnoses_icd.icd_code LIKE '250.0%'  -- T2DM
      AND diagnoses_icd.icd_code LIKE '%428%'  -- Heart Failure
  ),
  
  -- Filter for LOS >= 72h
  los_72h AS (
    SELECT 
      subject_id, 
      hadm_id,
      TIMESTAMPDIFF(HOUR, admittime, dischtime) AS los_hours
    FROM 
      patients_of_interest
    WHERE 
      TIMESTAMPDIFF(HOUR, admittime, dischtime) >= 72
  ),
  
  -- Identify insulin therapy in first 72h and last 48h
  insulin_therapy AS (
    SELECT 
      subject_id,
      hadm_id,
      starttime,
      drug_type
    FROM 
      `physionet-data.mimiciv_3_1_hosp.prescriptions`
    WHERE 
      drug_type = 'Insulin'
  ),
  
  -- Calculate percent initiating basal, bolus, basal-bolus, sliding-scale insulin
  insulin_initiation AS (
    SELECT 
      it.subject_id,
      it.hadm_id,
      CASE 
        WHEN it.drug_type LIKE 'Basal' THEN 'Basal'
        WHEN it.drug_type LIKE 'Bolus' THEN 'Bolus'
        WHEN it.drug_type LIKE 'Basal-Bolus' THEN 'Basal-Bolus'
        WHEN it.drug_type LIKE 'Sliding-Scale' THEN 'Sliding-Scale'
        ELSE 'Other'
      END AS insulin_type
    FROM 
      insulin_therapy it
  )

SELECT 
  -- Final calculation for percentages and differences
  insulin_type,
  COUNT(*) AS total_patients,
  -- Add calculations for percent and absolute percentage-point differences here
FROM 
  insulin_initiation
GROUP BY 
  insulin_type;