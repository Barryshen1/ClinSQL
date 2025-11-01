WITH 
patients_filtered AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 58 AND 68
),
admissions_filtered AS (
  SELECT hadm_id, subject_id, admittime, dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  WHERE DATETIME_DIFF(dischtime, admittime, HOUR) >= 72
),
conditions AS (
  SELECT DISTINCT diag.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
    ON diag.icd_code = d_icd.icd_code AND diag.icd_version = d_icd.icd_version
  WHERE (LOWER(d_icd.long_title) LIKE '%type 2 diabetes%' OR LOWER(d_icd.long_title) LIKE '%diabetes type 2%')
    AND (LOWER(d_icd.long_title) LIKE '%heart failure%' OR LOWER(d_icd.long_title) LIKE '%cardiac failure%')
),
cohort AS (
  SELECT a.hadm_id
  FROM admissions_filtered a
  JOIN conditions c ON a.hadm_id = c.hadm_id
  JOIN patients_filtered p ON a.subject_id = p.subject_id
),
glp1_agonists AS (
  SELECT DISTINCT pr.hadm_id, 
         CASE 
           WHEN DATETIME_DIFF(pr.starttime, a.admittime, HOUR) <= 72 THEN 'first_72h'
           WHEN DATETIME_DIFF(pr.starttime, a.dischtime, HOUR) >= -12 THEN 'last_12h'
           ELSE 'other'
         END AS timing
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN cohort c ON pr.hadm_id = c.hadm_id
  JOIN admissions_filtered a ON pr.hadm_id = a.hadm_id
  WHERE LOWER(pr.drug) LIKE '%liraglutide%' OR LOWER(pr.drug) LIKE '%semaglutide%' 
    OR LOWER(pr.drug) LIKE '%exenatide%' OR LOWER(pr.drug) LIKE '%dulaglutide%' 
    OR LOWER(pr.drug) LIKE '%albiglutide%'  
),
glp1_first_72h AS (
  SELECT COUNT(DISTINCT hadm_id) AS count_first_72h
  FROM glp1_agonists
  WHERE timing = 'first_72h'
),
glp1_last_12h AS (
  SELECT COUNT(DISTINCT hadm_id) AS count_last_12h
  FROM glp1_agonists
  WHERE timing = 'last_12h'
),
total_cohort AS (
  SELECT COUNT(DISTINCT hadm_id) AS total_count
  FROM cohort
)
SELECT 
  SAFE_DIVIDE(count_first_72h, total_count) * 100 AS percent_first_72h,
  SAFE_DIVIDE(count_last_12h, total_count) * 100 AS percent_last_12h,
  (SAFE_DIVIDE(count_first_72h, total_count) - SAFE_DIVIDE(count_last_12h, total_count)) * 100 AS absolute_diff_pp
FROM glp1_first_72h, glp1_last_12h, total_cohort;