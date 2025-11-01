WITH cohort AS (
  -- Base cohort: males 87-97 with sepsis (no shock)
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON a.hadm_id = d.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
  ON d.icd_code = icd.icd_code AND CAST(d.icd_version AS STRING) = icd.icd_version
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 87 AND 97
    AND (
      -- Sepsis codes (ICD-10 primary, include unspecified for broad coverage)
      (d.icd_version = 10 AND d.icd_code LIKE 'A41%')
      OR (d.icd_version = 10 AND d.icd_code LIKE 'A40%')
      OR (d.icd_version = 9 AND d.icd_code LIKE '038%')  -- ICD-9 sepsis equivalents
      OR (d.icd_version = 9 AND d.icd_code = '99591')    -- Sepsis ICD-9
    )
    AND NOT EXISTS (
      -- Exclude any admission with septic shock
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2 
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd2 
      ON d2.icd_code = icd2.icd_code AND CAST(d2.icd_version AS STRING) = icd2.icd_version
      WHERE d2.hadm_id = a.hadm_id 
      AND (
        (d2.icd_version = 10 AND d2.icd_code LIKE 'R65.2%')
        OR (d2.icd_version = 9 AND d2.icd_code = '78552')
      )
    )
),

los_groups AS (
  -- Add LOS groups
  SELECT 
    *,
    DATE_DIFF(DATE(dischtime), DATE(admittime), DAY) AS los_days,
    CASE 
      WHEN DATE_DIFF(DATE(dischtime), DATE(admittime), DAY) BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN DATE_DIFF(DATE(dischtime), DATE(admittime), DAY) BETWEEN 4 AND 7 THEN '4-7 days'
    END AS los_bin
  FROM cohort
  WHERE DATE_DIFF(DATE(dischtime), DATE(admittime), DAY) BETWEEN 1 AND 7
),

diagnostic_procedures AS (
  -- ICD diagnostic procedures (focus on valid diagnostic categories)
  SELECT 
    a.hadm_id,
    'icd' AS source,
    p.icd_code AS procedure_code
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  ON a.hadm_id = p.hadm_id
  WHERE 
    p.icd_version = 10
    AND (
      p.icd_code LIKE '0W3%'  -- Diagnostic imaging/ultrasound
      OR p.icd_code LIKE '0?9%'  -- Biopsies, endoscopies (diagnostic)
    )
  
  UNION ALL
  
  -- HCPCS diagnostic procedures
  SELECT 
    a.hadm_id,
    'hcpcs' AS source,
    h.hcpcs_cd AS procedure_code
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  ON a.hadm_id = h.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_hcpcs` dh
  ON h.hcpcs_cd = dh.code
  WHERE 
    dh.category LIKE '%Diagnostic%' 
    OR dh.category LIKE '%Laboratory%'
    OR dh.category LIKE '%Radiology%'
)

-- Aggregate: mean number of unique diagnostic procedures per LOS group
SELECT 
  lg.los_bin,
  COUNT(DISTINCT lg.hadm_id) AS n_admissions,
  AVG(COALESCE(dp_count.num_procedures, 0)) AS mean_diagnostic_procedures
FROM 
  los_groups lg
LEFT JOIN (
  SELECT 
    hadm_id,
    COUNT(DISTINCT procedure_code) AS num_procedures
  FROM 
    diagnostic_procedures
  GROUP BY hadm_id
) dp_count
ON lg.hadm_id = dp_count.hadm_id
GROUP BY lg.los_bin
ORDER BY 
  CASE los_bin 
    WHEN '1-3 days' THEN 1 
    WHEN '4-7 days' THEN 2 
  END;