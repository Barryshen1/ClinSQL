WITH cohort AS (
  -- Patients: female, age between 81 and 91 at anchor year
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  -- age filter
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 81 AND 91
),
diag_flags AS (
  -- Flag admissions with both T2DM and HF
  SELECT hadm_id,
         MAX(CASE WHEN (d.icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^250[.]..*[02]$'))
                     OR (d.icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^E11')) THEN 1 ELSE 0 END) AS has_t2dm,
         MAX(CASE WHEN (d.icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^428'))
                     OR (d.icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^I50')) THEN 1 ELSE 0 END) AS has_hf
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  GROUP BY hadm_id
),
eligible AS (
  SELECT c.*
  FROM cohort c
  JOIN diag_flags f
    ON c.hadm_id = f.hadm_id
  WHERE f.has_t2dm = 1
    AND f.has_hf = 1
),
rx_classes AS (
  SELECT e.hadm_id, 
         e.admittime,
         e.dischtime,
         starttime,
         stoptime,
         UPPER(drug) AS drug_upper,
         CASE 
           WHEN REGEXP_CONTAINS(UPPER(drug), r'METFORMIN') THEN 'Metformin'
           WHEN REGEXP_CONTAINS(UPPER(drug), r'GLIPIZIDE|GLIMEPIRIDE|GLYBURIDE|GLICLAZIDE|CHLORPROPAMIDE|TOLBUTAMIDE') THEN 'Sulfonylurea'
           WHEN REGEXP_CONTAINS(UPPER(drug), r'SITAGLIPTIN|SAXAGLIPTIN|LINAGLIPTIN|ALOGLIPTIN') THEN 'DPP4 inhibitor'
           WHEN REGEXP_CONTAINS(UPPER(drug), r'CANAGLIFLOZIN|DAPAGLIFLOZIN|EMPAGLIFLOZIN|ERTUGLIFLOZIN') THEN 'SGLT2 inhibitor'
           WHEN REGEXP_CONTAINS(UPPER(drug), r'PIOGLITAZONE|ROSIGLITAZONE') THEN 'TZD'
         END AS drug_class
  FROM eligible e
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON e.hadm_id = pr.hadm_id
  WHERE UPPER(route) LIKE '%PO%' -- oral route
),
window_flags AS (
  SELECT
    hadm_id,
    drug_class,
    MAX(CASE WHEN drug_class IS NOT NULL
                  AND starttime <= TIMESTAMP_ADD(admittime, INTERVAL 72 HOUR)
                  AND stoptime  >= admittime
             THEN 1 ELSE 0 END) AS in_first_72h,
    MAX(CASE WHEN drug_class IS NOT NULL
                  AND starttime <= dischtime
                  AND stoptime  >= TIMESTAMP_SUB(dischtime, INTERVAL 48 HOUR)
             THEN 1 ELSE 0 END) AS in_last_48h
  FROM rx_classes
  WHERE drug_class IS NOT NULL
  GROUP BY hadm_id, drug_class
),
agg AS (
  SELECT
    drug_class,
    COUNT(DISTINCT CASE WHEN in_first_72h = 1 THEN hadm_id END) AS first72_count,
    COUNT(DISTINCT CASE WHEN in_last_48h = 1 THEN hadm_id END) AS last48_count,
    COUNT(DISTINCT hadm_id) AS total_admissions
  FROM window_flags
  GROUP BY drug_class
)
SELECT
  drug_class,
  first72_count,
  ROUND(first72_count / total_admissions * 100, 1) AS first72_prevalence_pct,
  last48_count,
  ROUND(last48_count / total_admissions * 100, 1) AS last48_prevalence_pct,
  ROUND( (first72_count / total_admissions * 100) - (last48_count / total_admissions * 100), 1) AS abs_pp_difference
FROM agg
ORDER BY drug_class;