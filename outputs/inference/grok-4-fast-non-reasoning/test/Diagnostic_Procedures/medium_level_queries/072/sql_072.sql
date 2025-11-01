WITH filtered_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) + 1 AS los_days,
    CASE 
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) + 1 BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) + 1 BETWEEN 5 AND 8 THEN '5-8 days'
    END AS los_bin
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
    AND a.hospital_expire_flag = 0
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) + 1 BETWEEN 1 AND 8
),
pancreatitis_adms AS (
  SELECT DISTINCT
    fa.hadm_id,
    fa.subject_id,
    MAX(CASE WHEN di.seq_num = 1 THEN 1 ELSE 0 END) AS is_primary
  FROM 
    filtered_admissions fa
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  ON fa.hadm_id = di.hadm_id 
    AND CAST(fa.subject_id AS STRING) = di.subject_id
  WHERE 
    ((di.icd_version = '10' AND di.icd_code LIKE 'K85%')
     OR (di.icd_version = '9' AND di.icd_code LIKE '577.0%'))
  GROUP BY 
    fa.hadm_id, fa.subject_id
  HAVING 
    COUNT(*) > 0  -- Admissions with any pancreatitis diagnosis (primary or secondary)
),
procedure_counts AS (
  SELECT 
    pa.hadm_id,
    pa.is_primary,
    fa.los_bin,
    COUNT(DISTINCT pi.icd_code) AS num_diagnostic_procedures
  FROM 
    pancreatitis_adms pa
  INNER JOIN 
    filtered_admissions fa
  ON pa.hadm_id = fa.hadm_id
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  ON pa.hadm_id = pi.hadm_id 
    AND CAST(pa.subject_id AS STRING) = pi.subject_id
  WHERE 
    ((pi.icd_version = '10' AND pi.icd_code LIKE '0%')
     OR (pi.icd_version = '9' AND pi.icd_code LIKE '7%'))  -- Diagnostic procedures (broad filter)
  GROUP BY 
    pa.hadm_id, pa.is_primary, fa.los_bin
)
SELECT 
  los_bin,
  is_primary,
  AVG(num_diagnostic_procedures) AS mean_procedures,
  MIN(num_diagnostic_procedures) AS min_procedures,
  MAX(num_diagnostic_procedures) AS max_procedures
FROM 
  procedure_counts
GROUP BY 
  los_bin, is_primary
ORDER BY 
  los_bin, is_primary;