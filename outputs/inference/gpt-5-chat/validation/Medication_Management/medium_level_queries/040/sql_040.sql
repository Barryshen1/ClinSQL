WITH cohort AS (
  SELECT p.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  -- Age and gender filter
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 36 AND 46
),
dx_diabetes AS (
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code LIKE '250%')
     OR (icd_version = 10 AND icd_code LIKE 'E10%' )
     OR (icd_version = 10 AND icd_code LIKE 'E11%' )
     OR (icd_version = 10 AND icd_code LIKE 'E12%' )
     OR (icd_version = 10 AND icd_code LIKE 'E13%' )
     OR (icd_version = 10 AND icd_code LIKE 'E14%' )
  GROUP BY hadm_id
),
dx_hf AS (
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code LIKE '428%')
     OR (icd_version = 10 AND icd_code LIKE 'I50%')
  GROUP BY hadm_id
),
cohort_with_dx AS (
  SELECT c.*
  FROM cohort c
  JOIN dx_diabetes d1 ON c.hadm_id = d1.hadm_id
  JOIN dx_hf d2 ON c.hadm_id = d2.hadm_id
),
rx_class AS (
  SELECT pr.subject_id, pr.hadm_id, LOWER(pr.drug) AS drug_lower,
         pr.starttime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
),
class_flags AS (
  SELECT r.subject_id, r.hadm_id,
    CASE 
      WHEN r.drug_lower LIKE '%insulin%' 
        OR r.drug_lower LIKE '%metformin%'
        OR r.drug_lower LIKE '%glipizide%'
        OR r.drug_lower LIKE '%glyburide%'
        OR r.drug_lower LIKE '%sitagliptin%'
        OR r.drug_lower LIKE '%pioglitazone%'
        OR r.drug_lower LIKE '%empagliflozin%'
        OR r.drug_lower LIKE '%dapagliflozin%'
        OR r.drug_lower LIKE '%canagliflozin%'
      THEN 'Antidiabetic'
      WHEN r.drug_lower LIKE '%metoprolol%' 
        OR r.drug_lower LIKE '%carvedilol%'
        OR r.drug_lower LIKE '%atenolol%'
        OR r.drug_lower LIKE '%bisoprolol%'
        OR r.drug_lower LIKE '%propranolol%'
        OR r.drug_lower LIKE '%nebivolol%'
        OR r.drug_lower LIKE '%lisinopril%'
        OR r.drug_lower LIKE '%enalapril%'
        OR r.drug_lower LIKE '%ramipril%'
        OR r.drug_lower LIKE '%captopril%'
        OR r.drug_lower LIKE '%losartan%'
        OR r.drug_lower LIKE '%valsartan%'
        OR r.drug_lower LIKE '%sacubitril%'
        OR r.drug_lower LIKE '%furosemide%'
        OR r.drug_lower LIKE '%torsemide%'
        OR r.drug_lower LIKE '%bumetanide%'
      THEN 'Cardiac'
      ELSE NULL
    END AS drug_class,
    r.starttime
  FROM rx_class r
  WHERE r.drug_lower IS NOT NULL
),
cohort_rx AS (
  SELECT c.*, f.drug_class, f.starttime
  FROM cohort_with_dx c
  JOIN class_flags f
    ON c.subject_id = f.subject_id
   AND c.hadm_id = f.hadm_id
  WHERE f.drug_class IS NOT NULL
),
window_flags AS (
  SELECT DISTINCT
    subject_id, hadm_id, drug_class,
    CASE WHEN starttime BETWEEN admittime AND admittime + INTERVAL 48 HOUR
         THEN 1 ELSE 0 END AS first48h_flag,
    CASE WHEN starttime BETWEEN dischtime - INTERVAL 12 HOUR AND dischtime
         THEN 1 ELSE 0 END AS last12h_flag
  FROM cohort_rx
),
agg_patient_flags AS (
  SELECT drug_class,
         subject_id, hadm_id,
         MAX(first48h_flag) AS first48h_any,
         MAX(last12h_flag) AS last12h_any
  FROM window_flags
  GROUP BY drug_class, subject_id, hadm_id
),
counts AS (
  SELECT 
    drug_class,
    SUM(first48h_any) AS first48h_count,
    SUM(last12h_any) AS last12h_count
  FROM agg_patient_flags
  GROUP BY drug_class
),
total_patients AS (
  SELECT COUNT(DISTINCT subject_id) AS total_n
  FROM cohort_with_dx
)
SELECT 
  c.drug_class,
  ROUND(c.first48h_count / t.total_n * 100, 2) AS first48h_pct,
  ROUND(c.last12h_count / t.total_n * 100, 2) AS last12h_pct,
  ROUND((c.first48h_count / t.total_n * 100) - (c.last12h_count / t.total_n * 100), 2) AS abs_diff_pp
FROM counts c
CROSS JOIN total_patients t
ORDER BY drug_class;