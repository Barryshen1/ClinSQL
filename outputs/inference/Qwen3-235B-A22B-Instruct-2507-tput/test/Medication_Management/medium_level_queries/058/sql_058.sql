WITH patient_cohort AS (
  SELECT DISTINCT a.hadm_id, a.subject_id, a.admittime, a.dischtime,
    p.gender,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 36 AND 46
),
t2dm_hf_patients AS (
  SELECT pc.hadm_id, pc.admittime, pc.dischtime
  FROM patient_cohort pc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON pc.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE (d.icd_code LIKE 'E11%' AND di.icd_version = 10)  -- T2DM
     OR (d.icd_code LIKE 'I50%' AND di.icd_version = 10)  -- Heart Failure
  GROUP BY pc.hadm_id, pc.admittime, pc.dischtime
  HAVING COUNT(DISTINCT CASE WHEN d.icd_code LIKE 'E11%' THEN 1 END) >= 1
     AND COUNT(DISTINCT CASE WHEN d.icd_code LIKE 'I50%' THEN 1 END) >= 1
),
antidiabetics AS (
  SELECT 
    t2dm_hf_patients.hadm_id,
    p.starttime,
    p.drug,
    CASE
      WHEN LOWER(p.drug) LIKE '%metformin%' THEN 'Biguanide'
      WHEN LOWER(p.drug) LIKE '%sulfonylurea%' OR LOWER(p.drug) IN ('glipizide', 'glyburide', 'glimipiride') THEN 'Sulfonylurea'
      WHEN LOWER(p.drug) LIKE '%thiazolidinedione%' OR LOWER(p.drug) IN ('pioglitazone', 'rosiglitazone') THEN 'Thiazolidinedione'
      WHEN LOWER(p.drug) LIKE '%dpp4%' OR LOWER(p.drug) LIKE '%gliptin%' THEN 'DPP-4 Inhibitor'
      WHEN LOWER(p.drug) LIKE '%glp1%' OR LOWER(p.drug) LIKE '%agonist%' AND LOWER(p.drug) LIKE '%glp%' THEN 'GLP-1 Receptor Agonist'
      WHEN LOWER(p.drug) LIKE '%sglt2%' OR LOWER(p.drug) LIKE '%flozin%' THEN 'SGLT2 Inhibitor'
      WHEN LOWER(p.drug) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(p.drug) LIKE '%meglitinide%' OR LOWER(p.drug) IN ('repaglinide', 'nateglinide') THEN 'Meglitinide'
      ELSE 'Other'
    END AS drug_class
  FROM t2dm_hf_patients
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON t2dm_hf_patients.hadm_id = p.hadm_id
  WHERE p.starttime IS NOT NULL
),
windows AS (
  SELECT 
    a.hadm_id,
    a.drug_class,
    -- First 12h of admission
    CASE WHEN a.starttime >= p.admittime AND a.starttime <= p.admittime + INTERVAL '12' HOUR THEN 1 ELSE 0 END AS in_first_12h,
    -- Final 48h before discharge
    CASE WHEN a.starttime >= p.dischtime - INTERVAL '48' HOUR AND a.starttime < p.dischtime THEN 1 ELSE 0 END AS in_final_48h
  FROM antidiabetics a
  JOIN t2dm_hf_patients p ON a.hadm_id = p.hadm_id
),
class_patient_initiation AS (
  SELECT 
    drug_class,
    hadm_id,
    MAX(in_first_12h) AS initiated_first_12h,
    MAX(in_final_48h) AS initiated_final_48h
  FROM windows
  GROUP BY drug_class, hadm_id
),
summary AS (
  SELECT 
    drug_class,
    AVG(1.0 * initiated_first_12h) * 100 AS pct_initiated_first_12h,
    AVG(1.0 * initiated_final_48h) * 100 AS pct_initiated_final_48h
  FROM class_patient_initiation
  GROUP BY drug_class
  HAVING COUNT(*) >= 1  -- Ensure at least one patient
)
SELECT 
  drug_class,
  ROUND(pct_initiated_first_12h, 2) AS pct_first_12h,
  ROUND(pct_initiated_final_48h, 2) AS pct_final_48h,
  ROUND(pct_initiated_final_48h - pct_initiated_first_12h, 2) AS net_change_pp
FROM summary
ORDER BY net_change_pp DESC;