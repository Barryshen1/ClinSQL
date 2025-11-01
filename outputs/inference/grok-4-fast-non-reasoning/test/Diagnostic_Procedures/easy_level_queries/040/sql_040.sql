WITH eligible_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON p.subject_id = i.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
),
patient_procedure_counts AS (
  SELECT 
    ep.subject_id,
    COUNT(DISTINCT pe.itemid) AS distinct_ecg_telemetry_procedures
  FROM eligible_patients ep
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON ep.subject_id = i.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe 
      ON i.subject_id = pe.subject_id 
      AND i.stay_id = pe.stay_id
      AND pe.itemid IN (
        2297,  -- ECG details
        2298,  -- Rhythm
        3601,  -- ECG rate
        228163, -- ECG axis
        228164, -- ECG interpretation
        228165, -- ECG interval
        228166, -- ECG voltage
        228167, -- ECG arrhythmia
        228168, -- ECG ischemia
        228169, -- ECG infarct
        228170, -- ECG hypertrophy
        228171, -- ECG block
        228172  -- ECG other
      )
  GROUP BY ep.subject_id
)
SELECT 
  PERCENTILE_CONT(distinct_ecg_telemetry_procedures, 0.25) AS p25_distinct_ecg_telemetry_procedures
FROM patient_procedure_counts;