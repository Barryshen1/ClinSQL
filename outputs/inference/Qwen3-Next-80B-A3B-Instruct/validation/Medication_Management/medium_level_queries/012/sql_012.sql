WITH cohort AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1
    ON a.hadm_id = d1.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d1d
    ON d1.icd_code = d1d.icd_code AND d1.icd_version = d1d.icd_version
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
    ON a.hadm_id = d2.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d2d
    ON d2.icd_code = d2d.icd_code AND d2.icd_version = d2d.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND d1d.long_title LIKE '%Diabetes Mellitus, Type 2%'
    AND d2d.long_title LIKE '%Heart Failure%'
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 72
),
glp1_prescriptions AS (
  SELECT
    p.hadm_id,
    p.starttime,
    LOWER(p.drug) AS drug_name
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  WHERE LOWER(p.drug) IN (
    'liraglutide',
    'semaglutide',
    'exenatide',
    'dulaglutide',
    'lixisenatide',
    'albiglutide',
    'tirzepatide'
  )
),
cohort_with_glp1 AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    MAX(CASE WHEN gp.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 12 HOUR) THEN 1 ELSE 0 END) AS glp1_initiated_12h,
    MAX(CASE WHEN gp.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END) AS glp1_initiated_72h
  FROM cohort c
  LEFT JOIN glp1_prescriptions gp
    ON c.hadm_id = gp.hadm_id
  GROUP BY c.subject_id, c.hadm_id, c.admittime
)
SELECT
  AVG(glp1_initiated_12h) * 100 AS first_12h_initiation_rate_percent,
  AVG(glp1_initiated_72h) * 100 AS final_72h_prevalence_percent,
  (AVG(glp1_initiated_72h) - AVG(glp1_initiated_12h)) * 100 AS net_percentage_point_change
FROM cohort_with_glp1;