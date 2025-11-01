WITH patient_cohort AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 48 AND 58
),

admission_diagnoses AS (
  SELECT 
    di.hadm_id,
    MAX(CASE WHEN did.long_title LIKE '%diabetes mellitus type 2%' 
              OR di.icd_code LIKE 'E11%' THEN 1 ELSE 0 END) AS has_t2dm,
    MAX(CASE WHEN did.long_title LIKE '%heart failure%'
              OR di.icd_code LIKE 'I50%' THEN 1 ELSE 0 END) AS has_hf
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses did
    ON di.icd_code = did.icd_code AND di.icd_version = did.icd_version
  GROUP BY di.hadm_id
),

cohort_admissions AS (
  SELECT a.hadm_id, a.subject_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN patient_cohort pc ON a.subject_id = pc.subject_id
  INNER JOIN admission_diagnoses ad ON a.hadm_id = ad.hadm_id
  WHERE ad.has_t2dm = 1 AND ad.has_hf = 1
),

gpl1_drugs AS (
  SELECT DISTINCT ca.hadm_id,
    CASE WHEN p.starttime >= ca.admittime 
         AND p.starttime <= DATETIME_ADD(ca.admittime, INTERVAL 12 HOUR)
         THEN 1 ELSE 0 END AS in_first_12h,
    CASE WHEN p.starttime >= DATETIME_SUB(ca.dischtime, INTERVAL 12 HOUR)
         AND p.starttime <= ca.dischtime
         THEN 1 ELSE 0 END AS in_final_12h
  FROM `physionet-data.mimiciv_3_1_hosp`.prescriptions p
  INNER JOIN cohort_admissions ca
    ON p.hadm_id = ca.hadm_id
  WHERE LOWER(p.drug) LIKE '%liraglutide%'
     OR LOWER(p.drug) LIKE '%semaglutide%'
     OR LOWER(p.drug) LIKE '%dulaglutide%'
     OR LOWER(p.drug) LIKE '%exenatide%'
     OR LOWER(p.drug) LIKE '%ozempic%'
     OR LOWER(p.drug) LIKE '%rybelsus%'
     OR LOWER(p.drug) LIKE '%trulicity%'
     OR LOWER(p.drug) LIKE '%byetta%'
     OR LOWER(p.drug) LIKE '%victoza%'
     OR LOWER(p.drug) LIKE '%saxenda%'
)

SELECT
  100.0 * SUM(CASE WHEN in_first_12h = 1 THEN 1 ELSE 0 END) / COUNT(*) AS pct_first_12h,
  100.0 * SUM(CASE WHEN in_final_12h = 1 THEN 1 ELSE 0 END) / COUNT(*) AS pct_final_12h,
  100.0 * SUM(CASE WHEN in_final_12h = 1 THEN 1 ELSE 0 END) / COUNT(*) 
    - 100.0 * SUM(CASE WHEN in_first_12h = 1 THEN 1 ELSE 0 END) / COUNT(*) AS net_change
FROM (
  SELECT 
    hadm_id,
    MAX(in_first_12h) AS in_first_12h,
    MAX(in_final_12h) AS in_final_12h
  FROM gpl1_drugs
  GROUP BY hadm_id
);