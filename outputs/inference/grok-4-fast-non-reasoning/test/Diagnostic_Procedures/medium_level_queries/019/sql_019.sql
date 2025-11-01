WITH filtered_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) + 1 AS los_days,
    CASE 
      WHEN DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) + 1 BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) + 1 BETWEEN 5 AND 7 THEN '5-7 days'
    END AS los_category
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE 
    CAST(p.gender AS STRING) = CAST('M' AS STRING)
    AND CAST(p.anchor_age AS INT64) BETWEEN 42 AND 52
    AND a.hospital_expire_flag = 0
    AND a.dischtime IS NOT NULL
    AND d.icd_version = '10'
    AND d.icd_code LIKE 'K85%'
),
procedure_counts AS (
  SELECT 
    fa.subject_id,
    fa.hadm_id,
    fa.los_category,
    COUNT(DISTINCT pi.seq_num) AS num_diagnostic_procedures
  FROM 
    filtered_admissions fa
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    ON fa.hadm_id = pi.hadm_id
    AND pi.icd_version = '10'
    AND (pi.icd_code LIKE '87%' OR pi.icd_code LIKE '88%' OR pi.icd_code LIKE '89%')  -- Diagnostic procedures (e.g., imaging, endoscopy)
  WHERE 
    fa.los_category IS NOT NULL
  GROUP BY 
    fa.subject_id, fa.hadm_id, fa.los_category
)
SELECT 
  los_category,
  COUNT(DISTINCT hadm_id) AS admission_count,
  COUNT(DISTINCT subject_id) AS patient_count,
  ROUND(AVG(num_diagnostic_procedures), 2) AS mean_procedures,
  MIN(num_diagnostic_procedures) AS min_procedures,
  MAX(num_diagnostic_procedures) AS max_procedures
FROM 
  (SELECT 
     fa.subject_id,
     fa.hadm_id,
     fa.los_category,
     COALESCE(pc.num_diagnostic_procedures, 0) AS num_diagnostic_procedures
   FROM filtered_admissions fa 
   LEFT JOIN procedure_counts pc 
     ON fa.hadm_id = pc.hadm_id AND fa.los_category = pc.los_category)
WHERE los_category IS NOT NULL
GROUP BY 
  los_category
ORDER BY 
  MIN(los_days);