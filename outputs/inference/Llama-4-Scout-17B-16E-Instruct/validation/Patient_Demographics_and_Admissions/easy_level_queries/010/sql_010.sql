WITH 
  -- Filter patients by age and gender
  target_patients AS (
    SELECT subject_id, anchor_age, gender
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE anchor_age BETWEEN 48 AND 58 AND gender = 'F'
  ),
  
  -- Identify ICU stays for target patients with AKI
  ak_i_stays AS (
    SELECT DISTINCT i.stay_id, i.subject_id
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
    JOIN target_patients tp ON i.subject_id = tp.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
    WHERE d.icd_code LIKE '%584%'  -- Example for AKI ICD code
  ),
  
  -- Calculate ICU LOS
  icu_los AS (
    SELECT 
      i.stay_id,
      DATE_DIFF(TIMESTAMP(i.outtime), TIMESTAMP(i.intime), DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  )

-- Calculate 25th percentile of ICU LOS for AKI patients
SELECT 
  APPROX_QUANTILES(los_days, 0.25)[OFFSET(1)] AS percentile_25_los
FROM 
  icu_los
  JOIN ak_i_stays ON icu_los.stay_id = ak_i_stays.stay_id;