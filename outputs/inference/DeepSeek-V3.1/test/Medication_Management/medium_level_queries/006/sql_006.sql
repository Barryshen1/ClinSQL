WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON adm.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d 
        ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
      WHERE diag.subject_id = adm.subject_id
        AND diag.hadm_id = adm.hadm_id
        AND d.long_title LIKE '%Type 2 diabetes%'
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d 
        ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
      WHERE diag.subject_id = adm.subject_id
        AND diag.hadm_id = adm.hadm_id
        AND d.long_title LIKE '%Heart failure%'
    )
),
glp1_first72 AS (
  SELECT 
    c.subject_id,
    c.hadm_id
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.hadm_id = p.hadm_id
  WHERE LOWER(p.drug) LIKE '%liraglutide%'
     OR LOWER(p.drug) LIKE '%semaglutide%'
     OR LOWER(p.drug) LIKE '%dulaglutide%'
     OR LOWER(p.drug) LIKE '%exenatide%'
     OR LOWER(p.drug) LIKE '%lixisenatide%'
     OR LOWER(p.drug) LIKE '%glp%'
  AND LOWER(p.route) LIKE '%subcut%'
  AND p.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
  GROUP BY c.subject_id, c.hadm_id
),
glp1_last48 AS (
  SELECT 
    c.subject_id,
    c.hadm_id
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.hadm_id = p.hadm_id
  WHERE LOWER(p.drug) LIKE '%liraglutide%'
     OR LOWER(p.drug) LIKE '%semaglutide%'
     OR LOWER(p.drug) LIKE '%dulaglutide%'
     OR LOWER(p.drug) LIKE '%exenatide%'
     OR LOWER(p.drug) LIKE '%lixisenatide%'
     OR LOWER(p.drug) LIKE '%glp%'
  AND LOWER(p.route) LIKE '%subcut%'
  AND p.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 48 HOUR) AND c.dischtime
  GROUP BY c.subject_id, c.hadm_id
),
total_cohort AS (
  SELECT COUNT(*) AS total_count FROM cohort
)
SELECT 
  (SELECT COUNT(*) FROM glp1_first72) AS count_first72,
  (SELECT COUNT(*) FROM glp1_last48) AS count_last48,
  total_count,
  ROUND((SELECT COUNT(*) FROM glp1_first72) * 100.0 / total_count, 2) AS initiation_rate_first72,
  ROUND((SELECT COUNT(*) FROM glp1_last48) * 100.0 / total_count, 2) AS initiation_rate_last48,
  ROUND((SELECT COUNT(*) FROM glp1_last48) * 100.0 / total_count - (SELECT COUNT(*) FROM glp1_first72) * 100.0 / total_count, 2) AS absolute_difference_pp
FROM total_cohort;