WITH eligible_admissions AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
    AND a.admission_type IN ('EMERGENCY', 'ELECTIVE', 'URGENT', 'OBSERVATION')
    AND a.deathtime IS NULL
    AND DATETIME_DIFF(a.dischtime, a.admittime, HOUR) >= 36
    AND d.seq_num = 1
    AND (
      -- Acute heart failure (primary diagnosis)
      (d.icd_version = 'ICD-9' AND d.icd_code = '428') OR
      (d.icd_version = 'ICD-10' AND d.icd_code LIKE 'I50%')
    )
    AND EXISTS (
      -- Diabetes (any diagnosis)
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
      WHERE d2.subject_id = a.subject_id
        AND d2.hadm_id = a.hadm_id
        AND (
          (d2.icd_version = 'ICD-9' AND d2.icd_code LIKE '250%') OR
          (d2.icd_version = 'ICD-10' AND (d2.icd_code LIKE 'E10%' OR d2.icd_code LIKE 'E11%'))
        )
    )
),
glp1_starts AS (
  SELECT 
    ea.hadm_id,
    pr.starttime,
    ea.admittime,
    DATETIME_ADD(ea.admittime, INTERVAL 24 HOUR) AS first_24h_end,
    DATETIME_ADD(ea.dischtime, INTERVAL -12 HOUR) AS final_12h_start
  FROM eligible_admissions ea
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON ea.hadm_id = pr.hadm_id AND ea.subject_id = pr.subject_id
  WHERE pr.drug IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM UNNEST(['semaglutide', 'liraglutide', 'exenatide', 'dulaglutide']) AS pattern
      WHERE REGEXP_CONTAINS(LOWER(pr.drug), r'\b' || pattern || r'\b')
    )
    AND pr.route IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM UNNEST(['iv', 'sq', 'im', 'subcutaneous', 'intramuscular', 'intravenous']) AS pattern
      WHERE REGEXP_CONTAINS(LOWER(pr.route), r'\b' || pattern || r'\b')
    )
    AND pr.starttime >= ea.admittime
    AND pr.starttime < ea.dischtime
),
first_24h_counts AS (
  SELECT 
    COUNT(DISTINCT gs.hadm_id) AS first_24h_glp1,
    (SELECT COUNT(DISTINCT hadm_id) FROM eligible_admissions) AS total_admissions
  FROM glp1_starts gs
  WHERE gs.starttime < gs.first_24h_end
),
final_12h_counts AS (
  SELECT 
    COUNT(DISTINCT gs.hadm_id) AS final_12h_glp1,
    (SELECT COUNT(DISTINCT hadm_id) FROM eligible_admissions) AS total_admissions
  FROM glp1_starts gs
  WHERE gs.starttime >= gs.final_12h_start
)
SELECT 
  f.first_24h_glp1 * 100.0 / f.total_admissions AS first_24h_percent,
  n.final_12h_glp1 * 100.0 / n.total_admissions AS final_12h_percent
FROM first_24h_counts f
CROSS JOIN final_12h_counts n;