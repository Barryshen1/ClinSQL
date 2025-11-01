WITH 
  -- Identify female patients aged 59-69
  target_patients AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'F' AND anchor_age BETWEEN 59 AND 69
  ),
  
  -- Identify admissions with PCI procedure
  pci_admissions AS (
    SELECT a.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p ON a.hadm_id = p.hadm_id
    JOIN target_patients tp ON a.subject_id = tp.subject_id
    WHERE p.icd_code LIKE '36%'  -- PCI procedure code
  ),
  
  -- Calculate ICU length of stay for relevant admissions
  icu_stays AS (
    SELECT i.stay_id, i.hadm_id, 
           TIMESTAMP_DIFF(i.outtime, i.intime, 'MINUTE') / 60 AS icu_los_hours
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    JOIN pci_admissions pa ON i.hadm_id = pa.hadm_id
  )

-- Find maximum ICU length of stay
SELECT MAX(icu_los_hours) AS max_icu_los_hours
FROM icu_stays;