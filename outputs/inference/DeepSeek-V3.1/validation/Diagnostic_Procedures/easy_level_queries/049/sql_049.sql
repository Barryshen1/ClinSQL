WITH ecg_procedures AS (
  SELECT 
    p.subject_id,
    COUNT(DISTINCT picd.icd_code) AS distinct_ecg_codes
  FROM 
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` picd
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dicd 
    ON picd.icd_code = dicd.icd_code 
    AND picd.icd_version = dicd.icd_version
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON picd.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 81 AND 91
    AND LOWER(dicd.long_title) LIKE '%ecg%'
    OR LOWER(dicd.long_title) LIKE '%electrocardiogram%'
    OR LOWER(dicd.long_title) LIKE '%ekg%'
    OR LOWER(dicd.long_title) LIKE '%telemetry%'
  GROUP BY 
    p.subject_id
)
SELECT 
  STDDEV(distinct_ecg_codes) AS sd_distinct_ecg_codes
FROM 
  ecg_procedures;