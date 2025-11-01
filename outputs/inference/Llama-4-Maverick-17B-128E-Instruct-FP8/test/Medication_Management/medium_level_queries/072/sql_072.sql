WITH patient_population AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON a.subject_id = diag.subject_id AND a.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 79 AND 89
  AND (d_diag.long_title LIKE '%Type 2 diabetes%' OR d_diag.long_title LIKE '%Diabetes type 2%')
  AND (d_diag.long_title LIKE '%Heart failure%' OR d_diag.long_title LIKE '%Cardiac failure%')
),
glp1_prescriptions AS (
  SELECT p.subject_id, p.hadm_id, pr.starttime, p.admittime, p.dischtime
  FROM patient_population p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr ON p.subject_id = pr.subject_id AND p.hadm_id = pr.hadm_id
  WHERE LOWER(pr.drug) LIKE '%liraglutide%' OR LOWER(pr.drug) LIKE '%semaglutide%' OR LOWER(pr.drug) LIKE '%exenatide%'
),
initiation_12hrs AS (
  SELECT subject_id, hadm_id, 
  MAX(CASE WHEN starttime <= TIMESTAMP_ADD(admittime, INTERVAL 12 HOUR) THEN 1 ELSE 0 END) AS initiated_12hrs
  FROM glp1_prescriptions
  GROUP BY subject_id, hadm_id, admittime
),
last_24hrs AS (
  SELECT subject_id, hadm_id, 
  MAX(CASE WHEN starttime >= TIMESTAMP_SUB(dischtime, INTERVAL 24 HOUR) THEN 1 ELSE 0 END) AS initiated_last24hrs
  FROM glp1_prescriptions
  GROUP BY subject_id, hadm_id, dischtime
),
counts AS (
  SELECT 
    COUNT(DISTINCT p.hadm_id) AS total_patients,
    COUNT(CASE WHEN i12.initiated_12hrs = 1 THEN 1 END) AS initiated_12hrs_count,
    COUNT(CASE WHEN l24.initiated_last24hrs = 1 THEN 1 END) AS initiated_last24hrs_count
  FROM patient_population p
  LEFT JOIN initiation_12hrs i12 USING (subject_id, hadm_id)
  LEFT JOIN last_24hrs l24 USING (subject_id, hadm_id)
)
SELECT 
  SAFE_DIVIDE(initiated_12hrs_count, total_patients) * 100 AS percent_initiated_12hrs,
  SAFE_DIVIDE(initiated_last24hrs_count, total_patients) * 100 AS percent_initiated_last24hrs,
  SAFE_DIVIDE(initiated_last24hrs_count - initiated_12hrs_count, total_patients) * 100 AS net_percentage_point_change
FROM counts;