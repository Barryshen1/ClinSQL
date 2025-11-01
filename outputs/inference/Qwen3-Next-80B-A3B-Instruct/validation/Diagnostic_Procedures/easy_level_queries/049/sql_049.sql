WITH ecg_telemetry_procedures AS (
  SELECT 
    p.subject_id,
    COUNT(DISTINCT pe.itemid) AS num_distinct_ecg_telemetry_codes
  FROM 
    physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN 
    physionet-data.mimiciv_3_1_icu.procedureevents pe
    ON p.subject_id = pe.subject_id
  INNER JOIN 
    physionet-data.mimiciv_3_1_icu.d_items di
    ON pe.itemid = di.itemid
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 81 AND 91
    AND (
      LOWER(di.label) LIKE '%ecg%'
      OR LOWER(di.label) LIKE '%telemetry%'
      OR LOWER(di.label) LIKE '%electrocardiogram%'
    )
  GROUP BY 
    p.subject_id
)
SELECT 
  STDDEV(num_distinct_ecg_telemetry_codes) AS sd_distinct_ecg_telemetry_codes_per_patient
FROM 
  ecg_telemetry_procedures;