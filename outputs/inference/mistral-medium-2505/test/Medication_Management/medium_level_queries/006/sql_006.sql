WITH
-- Define GLP-1 agonists (injectable forms)
glp1_agonists AS (
  SELECT DISTINCT drug
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE LOWER(drug) LIKE '%liraglutide%'
     OR LOWER(drug) LIKE '%exenatide%'
     OR LOWER(drug) LIKE '%dulaglutide%'
     OR LOWER(drug) LIKE '%semaglutide%'
     OR LOWER(drug) LIKE '%lixisenatide%'
     OR LOWER(drug) LIKE '%albiglutide%'
),

-- Get patients with T2DM and HF (any diagnosis position)
t2dm_hf_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1 ON a.hadm_id = d1.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2 ON a.hadm_id = d2.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag1 ON d1.icd_code = diag1.icd_code AND d1.icd_version = diag1.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag2 ON d2.icd_code = diag2.icd_code AND d2.icd_version = diag2.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
    AND (diag1.icd_code LIKE 'E11%' OR diag1.icd_code LIKE 'E11.%') -- T2DM
    AND (diag2.icd_code LIKE 'I50%' OR diag2.icd_code LIKE 'I50.%') -- HF
    AND d1.subject_id = d2.subject_id
    AND d1.hadm_id = d2.hadm_id
    AND d1.seq_num <> d2.seq_num -- Ensure different diagnoses
),

-- Get eligible admissions
eligible_admissions AS (
  SELECT a.hadm_id, a.subject_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN t2dm_hf_patients p ON a.subject_id = p.subject_id
  WHERE a.admission_type NOT LIKE '%EMERGENCY%'
    AND a.admission_type NOT LIKE '%OBSERVATION%'
    AND a.dischtime IS NOT NULL
),

-- Get GLP-1 initiations in first 72 hours
first_72h_initiations AS (
  SELECT DISTINCT e.hadm_id
  FROM eligible_admissions e
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr ON e.hadm_id = pr.hadm_id
  JOIN glp1_agonists g ON pr.drug = g.drug
  WHERE pr.starttime BETWEEN e.admittime AND TIMESTAMP_ADD(e.admittime, INTERVAL 72 HOUR)
    AND pr.starttime IS NOT NULL
),

-- Get GLP-1 initiations in last 48 hours
last_48h_initiations AS (
  SELECT DISTINCT e.hadm_id
  FROM eligible_admissions e
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr ON e.hadm_id = pr.hadm_id
  JOIN glp1_agonists g ON pr.drug = g.drug
  WHERE pr.starttime BETWEEN TIMESTAMP_SUB(e.dischtime, INTERVAL 48 HOUR) AND e.dischtime
    AND TIMESTAMP_DIFF(e.dischtime, e.admittime, HOUR) >= 72 -- Only admissions long enough to have a last 48h period
    AND pr.starttime IS NOT NULL
),

-- Count initiations
initiation_counts AS (
  SELECT
    COUNT(DISTINCT e.hadm_id) AS total_admissions,
    COUNT(DISTINCT f.hadm_id) AS first_72h_count,
    COUNT(DISTINCT l.hadm_id) AS last_48h_count
  FROM eligible_admissions e
  LEFT JOIN first_72h_initiations f ON e.hadm_id = f.hadm_id
  LEFT JOIN last_48h_initiations l ON e.hadm_id = l.hadm_id
)

-- Calculate rates and difference with NULL protection
SELECT
  total_admissions,
  first_72h_count,
  CASE
    WHEN total_admissions > 0 THEN ROUND((first_72h_count / total_admissions) * 100, 2)
    ELSE NULL
  END AS first_72h_rate,
  last_48h_count,
  CASE
    WHEN total_admissions > 0 THEN ROUND((last_48h_count / total_admissions) * 100, 2)
    ELSE NULL
  END AS last_48h_rate,
  CASE
    WHEN total_admissions > 0 THEN ROUND(ABS((first_72h_count / total_admissions) - (last_48h_count / total_admissions)) * 100, 2)
    ELSE NULL
  END AS absolute_difference_pp
FROM initiation_counts;