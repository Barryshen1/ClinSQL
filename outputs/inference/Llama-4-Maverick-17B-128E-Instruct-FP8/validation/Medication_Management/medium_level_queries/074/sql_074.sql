WITH cohort AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 48 AND 58
  AND p.subject_id IN (
    SELECT d.subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
    WHERE dicd.long_title LIKE '%Diabetes%' OR dicd.long_title LIKE '%Heart Failure%'
  )
),
admissions AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN cohort ON a.subject_id = cohort.subject_id
),
glp1_admin AS (
  SELECT DISTINCT e.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.emar` e
  JOIN admissions adm ON e.hadm_id = adm.hadm_id
  WHERE LOWER(e.medication) LIKE '%liraglutide%' OR LOWER(e.medication) LIKE '%semaglutide%'
  AND e.charttime BETWEEN adm.admittime AND TIMESTAMP_ADD(adm.admittime, INTERVAL 24 HOUR)
),
glp1_admin_last12 AS (
  SELECT DISTINCT e.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.emar` e
  JOIN admissions adm ON e.hadm_id = adm.hadm_id
  WHERE LOWER(e.medication) LIKE '%liraglutide%' OR LOWER(e.medication) LIKE '%semaglutide%'
  AND e.charttime BETWEEN TIMESTAMP_SUB(adm.dischtime, INTERVAL 12 HOUR) AND adm.dischtime
)
SELECT 
  COUNT(DISTINCT glp1_admin.hadm_id) / COUNT(DISTINCT admissions.hadm_id) * 100 AS prevalence_glp1_first24,
  COUNT(DISTINCT glp1_admin_last12.hadm_id) / COUNT(DISTINCT admissions.hadm_id) * 100 AS prevalence_glp1_last12
FROM admissions
LEFT JOIN glp1_admin ON admissions.hadm_id = glp1_admin.hadm_id
LEFT JOIN glp1_admin_last12 ON admissions.hadm_id = glp1_admin_last12.hadm_id;