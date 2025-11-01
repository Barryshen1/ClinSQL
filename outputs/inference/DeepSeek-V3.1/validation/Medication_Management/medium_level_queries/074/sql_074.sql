WITH cohort AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
      WHERE di.hadm_id = a.hadm_id
        AND d.long_title LIKE '%diabetes%'
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
      WHERE di.hadm_id = a.hadm_id
        AND d.long_title LIKE '%heart failure%'
    )
),
glp1_first_24h AS (
  SELECT 
    c.hadm_id,
    MAX(1) AS glp1_24h_flag
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` rx
    ON c.hadm_id = rx.hadm_id
  WHERE LOWER(rx.drug) LIKE '%glp%' 
    OR LOWER(rx.drug) LIKE '%semaglutide%'
    OR LOWER(rx.drug) LIKE '%liraglutide%'
    OR LOWER(rx.drug) LIKE '%dulaglutide%'
    OR LOWER(rx.drug) LIKE '%exenatide%'
    AND LOWER(rx.route) LIKE '%subq%' 
    OR LOWER(rx.route) LIKE '%subcut%'
    AND rx.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
  GROUP BY c.hadm_id
),
glp1_final_12h AS (
  SELECT 
    c.hadm_id,
    MAX(1) AS glp1_12h_flag
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` rx
    ON c.hadm_id = rx.hadm_id
  WHERE LOWER(rx.drug) LIKE '%glp%' 
    OR LOWER(rx.drug) LIKE '%semaglutide%'
    OR LOWER(rx.drug) LIKE '%liraglutide%'
    OR LOWER(rx.drug) LIKE '%dulaglutide%'
    OR LOWER(rx.drug) LIKE '%exenatide%'
    AND LOWER(rx.route) LIKE '%subq%' 
    OR LOWER(rx.route) LIKE '%subcut%'
    AND rx.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR) AND c.dischtime
  GROUP BY c.hadm_id
)
SELECT 
  COUNT(DISTINCT cohort.hadm_id) AS total_patients,
  COUNT(DISTINCT glp1_first_24h.hadm_id) AS glp1_first_24h_count,
  ROUND(COUNT(DISTINCT glp1_first_24h.hadm_id) * 100.0 / COUNT(DISTINCT cohort.hadm_id), 2) AS glp1_first_24h_percent,
  COUNT(DISTINCT glp1_final_12h.hadm_id) AS glp1_final_12h_count,
  ROUND(COUNT(DISTINCT glp1_final_12h.hadm_id) * 100.0 / COUNT(DISTINCT cohort.hadm_id), 2) AS glp1_final_12h_percent
FROM cohort
LEFT JOIN glp1_first_24h ON cohort.hadm_id = glp1_first_24h.hadm_id
LEFT JOIN glp1_final_12h ON cohort.hadm_id = glp1_final_12h.hadm_id;