WITH 
  -- Identify sepsis admissions
  sepsis_admissions AS (
    SELECT 
      a.hadm_id,
      a.subject_id
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON 
      a.hadm_id = d.hadm_id
    WHERE 
      d.icd_code LIKE ' sepsis%' 
      OR d.icd_code LIKE 'Septicemia%' 
      OR d.icd_code LIKE 'Sepsis%'
  ),

  -- Eligible patients
  eligible_patients AS (
    SELECT 
      p.subject_id,
      p.anchor_age,
      p.gender
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    WHERE 
      p.gender = 'F'
      AND p.anchor_age BETWEEN 58 AND 68
  ),

  -- ICU stays for eligible patients with sepsis
  icu_stays_eligible AS (
    SELECT 
      i.stay_id,
      i.subject_id,
      i.hadm_id,
      i.los
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays` i
    JOIN 
      sepsis_admissions s
    ON 
      i.hadm_id = s.hadm_id
      AND i.subject_id = s.subject_id
    JOIN 
      eligible_patients e
    ON 
      i.subject_id = e.subject_id
  )

-- Calculate median ICU LOS
SELECT 
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_icu_los
FROM 
  icu_stays_eligible;