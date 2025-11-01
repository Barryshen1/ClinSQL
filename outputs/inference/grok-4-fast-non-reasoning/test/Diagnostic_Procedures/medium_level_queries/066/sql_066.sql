WITH asthma_admissions AS (
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code AND CAST(d.icd_version AS STRING) = icd.icd_version
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 88 AND 98
    AND d.icd_version = 10
    AND d.icd_code LIKE 'J45%'
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),
procedure_counts AS (
  SELECT 
    aa.hadm_id,
    COUNT(DISTINCT pr.icd_code) AS num_diagnostic_procedures
  FROM 
    asthma_admissions aa
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON aa.hadm_id = pr.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` ip
    ON pr.icd_code = ip.icd_code AND CAST(pr.icd_version AS STRING) = ip.icd_version
  WHERE 
    (LOWER(ip.long_title) LIKE '%diagnostic%'
     OR LOWER(ip.long_title) LIKE '%test%'
     OR LOWER(ip.long_title) LIKE '%imaging%'
     OR LOWER(ip.long_title) LIKE '%biopsy%'
     OR LOWER(ip.long_title) LIKE '%endoscopy%')
  GROUP BY 
    aa.hadm_id
),
admissions_with_procs AS (
  SELECT 
    aa.*,
    COALESCE(pc.num_diagnostic_procedures, 0) AS num_procedures,
    CASE 
      WHEN aa.los BETWEEN 1 AND 3 THEN '1-3 days'
      ELSE '4-7 days'
    END AS los_bin
  FROM 
    asthma_admissions aa
  LEFT JOIN 
    procedure_counts pc
    ON aa.hadm_id = pc.hadm_id
)
SELECT 
  los_bin,
  PERCENTILE_CONT(0.25) OVER (PARTITION BY los_bin) AS p25_procedures,
  PERCENTILE_CONT(0.50) OVER (PARTITION BY los_bin) AS p50_procedures,
  PERCENTILE_CONT(0.75) OVER (PARTITION BY los_bin) AS p75_procedures
FROM 
  admissions_with_procs
GROUP BY 
  los_bin
ORDER BY 
  los_bin;