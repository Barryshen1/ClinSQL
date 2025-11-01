WITH eligible AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 58 AND 68
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 72
),
diags AS (
  SELECT
    e.hadm_id,
    MAX(CASE
          WHEN LOWER(dc.long_title) LIKE '%type 2 diabetes%' 
               OR LOWER(dc.long_title) LIKE '%diabetes mellitus type 2%'
               OR LOWER(dc.long_title) LIKE '%diabetes type 2%'
          THEN 1 ELSE 0 END) AS has_diabetes,
    MAX(CASE
          WHEN LOWER(dc.long_title) LIKE '%heart failure%' 
               OR LOWER(dc.long_title) LIKE '%congestive heart failure%'
          THEN 1 ELSE 0 END) AS has_heart_failure
  FROM eligible e
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    ON e.subject_id = diag.subject_id AND e.hadm_id = diag.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dc
    ON diag.icd_code = dc.icd_code AND diag.icd_version = dc.icd_version
  GROUP BY e.hadm_id
),
glp1_early AS (
  SELECT e.hadm_id,
         MAX(CASE WHEN p.starttime IS NOT NULL
                   AND p.starttime BETWEEN e.admittime AND TIMESTAMP_ADD(e.admittime, INTERVAL 72 HOUR)
                   THEN 1 ELSE 0 END) AS has_early_glp1
  FROM eligible e
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
    ON e.subject_id = p.subject_id AND e.hadm_id = p.hadm_id
  GROUP BY e.hadm_id
),
glp1_late AS (
  SELECT e.hadm_id,
         MAX(CASE WHEN p.starttime IS NOT NULL
                   AND p.starttime BETWEEN TIMESTAMP_SUB(e.dischtime, INTERVAL 12 HOUR) AND e.dischtime
                   THEN 1 ELSE 0 END) AS has_late_glp1
  FROM eligible e
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
    ON e.subject_id = p.subject_id AND e.hadm_id = p.hadm_id
  GROUP BY e.hadm_id
)
, summary AS (
  SELECT
    COUNT(*) AS total_admissions,
    SUM(ge.has_early_glp1) AS early_count,
    SUM(gl.has_late_glp1) AS late_count
  FROM eligible e
  JOIN diags d ON e.hadm_id = d.hadm_id
  LEFT JOIN glp1_early ge ON e.hadm_id = ge.hadm_id
  LEFT JOIN glp1_late gl ON e.hadm_id = gl.hadm_id
  WHERE d.has_diabetes = 1
    AND d.has_heart_failure = 1
)
SELECT
  total_admissions,
  ROUND(100.0 * early_count / total_admissions, 2) AS p_first72_percent,
  ROUND(100.0 * late_count / total_admissions, 2) AS p_final12_percent,
  ROUND(ABS((100.0 * early_count / total_admissions) - (100.0 * late_count / total_admissions)), 2) AS diff_pp
FROM summary;