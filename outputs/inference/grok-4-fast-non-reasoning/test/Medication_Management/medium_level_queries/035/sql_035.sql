WITH cohort AS (
  -- Define cohort: females 57-67 with diabetes and heart failure
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
    ON p.subject_id = d.subject_id 
    AND CAST(a.hadm_id AS STRING) = d.hadm_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 57 AND 67
    AND a.admission_type IN ('ADMITTED', 'EMERGENCY', 'OBSERVATION', 'URGENT')
    AND a.hadm_id IS NOT NULL
    AND (a.hospital_expire_flag = 0 OR a.hospital_expire_flag IS NULL)
    AND d.icd_version = '10'
    AND d.seq_num = 1  -- Primary diagnosis for specificity
    AND (
      -- Diabetes ICD-10: E08-E13
      d.icd_code LIKE 'E08%' OR d.icd_code LIKE 'E09%' OR d.icd_code LIKE 'E10%' 
      OR d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E12%' OR d.icd_code LIKE 'E13%'
    )
    AND EXISTS (
      -- Ensure heart failure ICD-10: I50 is also present for this admission
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
      WHERE d2.subject_id = a.subject_id 
      AND CAST(a.hadm_id AS STRING) = d2.hadm_id
      AND d2.icd_version = '10' 
      AND d2.icd_code LIKE 'I50%'
    )
),

glp1_first48 AS (
  -- GLP-1 RA prescriptions in first 48h
  SELECT 
    c.hadm_id,
    SUM(CASE WHEN LOWER(pr.drug) LIKE ANY ('%semaglutide%', '%liraglutide%', '%dulaglutide%', 
                                           '%exenatide%', '%albiglutide%', '%tirzepatide%') 
             AND pr.drug IS NOT NULL
             THEN 1 ELSE 0 END) AS num_glp1_first48
  FROM 
    cohort c
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.subject_id = pr.subject_id 
    AND CAST(c.hadm_id AS STRING) = pr.hadm_id
    AND pr.starttime >= c.admittime
    AND pr.starttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 2 DAY)
  GROUP BY 
    c.hadm_id
),

glp1_final12 AS (
  -- GLP-1 RA prescriptions in final 12h pre-discharge
  SELECT 
    c.hadm_id,
    SUM(CASE WHEN LOWER(pr.drug) LIKE ANY ('%semaglutide%', '%liraglutide%', '%dulaglutide%', 
                                           '%exenatide%', '%albiglutide%', '%tirzepatide%') 
             AND pr.drug IS NOT NULL
             THEN 1 ELSE 0 END) AS num_glp1_final12
  FROM 
    cohort c
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.subject_id = pr.subject_id 
    AND CAST(c.hadm_id AS STRING) = pr.hadm_id
    AND pr.starttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR)
    AND pr.starttime <= c.dischtime
  GROUP BY 
    c.hadm_id
),

aggregated AS (
  SELECT 
    COUNT(DISTINCT c.hadm_id) AS total_admissions,
    COUNT(DISTINCT f.hadm_id) AS admissions_with_glp1_first48,  -- Non-zero count implies presence
    COUNT(DISTINCT l.hadm_id) AS admissions_with_glp1_final12
  FROM 
    cohort c
  LEFT JOIN 
    glp1_first48 f ON c.hadm_id = f.hadm_id AND f.num_glp1_first48 > 0
  LEFT JOIN 
    glp1_final12 l ON c.hadm_id = l.hadm_id AND l.num_glp1_final12 > 0
)

SELECT 
  total_admissions,
  ROUND((admissions_with_glp1_first48 * 100.0 / total_admissions), 2) AS prevalence_first48_pct,
  ROUND((admissions_with_glp1_final12 * 100.0 / total_admissions), 2) AS prevalence_final12_pct,
  ROUND((admissions_with_glp1_final12 * 100.0 / total_admissions) - (admissions_with_glp1_first48 * 100.0 / total_admissions), 2) AS absolute_change_pct,
  ROUND(
    CASE 
      WHEN admissions_with_glp1_first48 > 0 
      THEN ((admissions_with_glp1_final12 * 100.0 / total_admissions) - (admissions_with_glp1_first48 * 100.0 / total_admissions)) 
           / (admissions_with_glp1_first48 * 100.0 / total_admissions) * 100
      ELSE 0 
    END, 2
  ) AS relative_change_pct
FROM 
  aggregated;