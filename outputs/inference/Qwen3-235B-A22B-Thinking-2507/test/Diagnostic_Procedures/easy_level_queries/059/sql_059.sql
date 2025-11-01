WITH eligible_admissions AS (
  SELECT 
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 76 AND 86
),

cardiac_procs AS (
  SELECT DISTINCT
    p.hadm_id,
    p.icd_code,
    p.icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%cardiac%'
),

counts_per_hadm AS (
  SELECT 
    e.hadm_id,
    COUNT(c.hadm_id) AS num_cardiac_procs
  FROM eligible_admissions e
  LEFT JOIN cardiac_procs c ON e.hadm_id = c.hadm_id
  GROUP BY e.hadm_id
)

SELECT 
  APPROX_QUANTILES(num_cardiac_procs, 1000)[OFFSET(750)] - 
  APPROX_QUANTILES(num_cardiac_procs, 1000)[OFFSET(250)] AS iqr
FROM counts_per_hadm;