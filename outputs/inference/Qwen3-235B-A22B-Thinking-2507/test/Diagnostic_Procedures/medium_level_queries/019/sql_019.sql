WITH filtered_admissions AS (
  SELECT 
    a.hadm_id,
    DATETIME_DIFF(a.dischtime, a.admittime, MINUTE) / (24 * 60) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 42 AND 52
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE 
        d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code = '5770')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'K85%')
        )
    )
),
diagnostic_procedures AS (
  SELECT 
    h.hadm_id,
    COUNT(*) AS num_procedures
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d 
    ON h.hcpcs_cd = d.code
  WHERE d.long_description LIKE '%Diagnostic Radiology%'
  GROUP BY h.hadm_id
),
admission_metrics AS (
  SELECT 
    fa.hadm_id,
    fa.los_days,
    COALESCE(dp.num_procedures, 0) AS num_procedures,
    CASE 
      WHEN fa.los_days >= 1 AND fa.los_days < 5 THEN '1-4'
      WHEN fa.los_days >= 5 AND fa.los_days < 8 THEN '5-7'
    END AS los_group
  FROM filtered_admissions fa
  LEFT JOIN diagnostic_procedures dp 
    ON fa.hadm_id = dp.hadm_id
)
SELECT 
  los_group,
  COUNT(*) AS patient_count,
  AVG(num_procedures) AS mean_procedures,
  MIN(num_procedures) AS min_procedures,
  MAX(num_procedures) AS max_procedures
FROM admission_metrics
WHERE los_group IS NOT NULL
GROUP BY los_group
ORDER BY 
  CASE los_group 
    WHEN '1-4' THEN 1 
    WHEN '5-7' THEN 2 
  END;