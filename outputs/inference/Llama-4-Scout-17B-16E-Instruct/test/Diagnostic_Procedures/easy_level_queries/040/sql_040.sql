WITH 
  -- Filter patients by age and gender
  target_patients AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE anchor_age BETWEEN 51 AND 61
    AND gender = 'M'
  ),

  -- Identify ECG/telemetry procedures
  ecg_procedures AS (
    SELECT 
      p.subject_id,
      pe.itemid
    FROM 
      `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    JOIN 
      target_patients p ON pe.subject_id = p.subject_id
    WHERE 
      pe.itemid IN (SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items` WHERE label LIKE '%ECG%' OR label LIKE '%telemetry%')
  ),

  -- Calculate counts of distinct procedures per patient
  patient_proc_counts AS (
    SELECT 
      subject_id,
      COUNT(DISTINCT itemid) AS proc_count
    FROM 
      ecg_procedures
    GROUP BY 
      subject_id
  )

-- Calculate the 25th percentile of distinct procedures per patient
SELECT 
  APPROX_QUANTILES(proc_count, 100)[OFFSET(25)] AS percentile_25
FROM 
  patient_proc_counts;