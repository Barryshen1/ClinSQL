WITH 
  -- Identify ECG/telemetry itemids
  ecg_itemids AS (
    SELECT itemid 
    FROM `physionet-data.mimiciv_3_1_icu.d_items` 
    WHERE label LIKE '%ECG%' OR label LIKE '%telemetry%'
  ),
  
  -- Get patient info
  patient_info AS (
    SELECT subject_id, anchor_age, gender
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'M' AND anchor_age BETWEEN 41 AND 51
  ),
  
  -- Get procedures for these patients
  patient_procedures AS (
    SELECT p.subject_id, pe.itemid
    FROM patient_info p
    JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe 
      ON p.subject_id = pe.subject_id
    WHERE pe.itemid IN (SELECT itemid FROM ecg_itemids)
  ),
  
  -- Calculate counts of distinct procedures per patient
  patient_procedure_counts AS (
    SELECT 
      subject_id, 
      COUNT(DISTINCT itemid) AS procedure_count
    FROM patient_procedures
    GROUP BY subject_id
  )

-- Calculate 75th percentile of distinct procedures per patient
SELECT 
  APPROX_QUANTILES(procedure_count, 100)[OFFSET(75)] AS percentile_75
FROM patient_procedure_counts;