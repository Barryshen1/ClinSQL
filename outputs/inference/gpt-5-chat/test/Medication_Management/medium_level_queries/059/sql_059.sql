WITH
-- 1. Identify admissions for 60-70 yo females with both T2DM and HF diagnosis
t2dm_hadm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE ( (icd_version = 9 AND icd_code LIKE '250%' AND RIGHT(icd_code,1) IN ('0','2'))
       OR (icd_version = 10 AND icd_code LIKE 'E11%') )
),
hf_hadm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE ( (icd_version = 9 AND icd_code LIKE '428%')
       OR (icd_version = 10 AND icd_code LIKE 'I50%') )
),
cohort AS (
  SELECT a.subject_id, a.hadm_id, p.gender, p.anchor_age, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN t2dm_hadm t2 ON a.hadm_id = t2.hadm_id
  JOIN hf_hadm hf ON a.hadm_id = hf.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 60 AND 70
),

-- 2. Classify prescriptions into drug classes
presc_classes AS (
  SELECT
    pr.hadm_id,
    pr.starttime,
    CASE
      WHEN LOWER(drug) LIKE '%metformin%' OR LOWER(drug) LIKE '%insulin%' 
        OR LOWER(drug) LIKE '%glipizide%' OR LOWER(drug) LIKE '%glyburide%' 
        OR LOWER(drug) LIKE '%glimepiride%' OR LOWER(drug) LIKE '%alogliptin%'
        OR LOWER(drug) LIKE '%linagliptin%' OR LOWER(drug) LIKE '%sitagliptin%'
        OR LOWER(drug) LIKE '%empagliflozin%' OR LOWER(drug) LIKE '%dapagliflozin%' 
        OR LOWER(drug) LIKE '%canagliflozin%' OR LOWER(drug) LIKE '%pioglitazone%'
        THEN 'Antidiabetic'
      WHEN LOWER(drug) LIKE '%metoprolol%' OR LOWER(drug) LIKE '%atenolol%'
        OR LOWER(drug) LIKE '%propranolol%' OR LOWER(drug) LIKE '%carvedilol%'
        OR LOWER(drug) LIKE '%bisoprolol%' OR LOWER(drug) LIKE '%nadolol%'
        THEN 'Beta-blocker'
      WHEN LOWER(drug) LIKE '%lisinopril%' OR LOWER(drug) LIKE '%ramipril%' OR LOWER(drug) LIKE '%enalapril%'
        OR LOWER(drug) LIKE '%captopril%' OR LOWER(drug) LIKE '%benazepril%' OR LOWER(drug) LIKE '%trandolapril%'
        OR LOWER(drug) LIKE '%quinapril%' OR LOWER(drug) LIKE '%perindopril%'
        OR LOWER(drug) LIKE '%losartan%' OR LOWER(drug) LIKE '%valsartan%' OR LOWER(drug) LIKE '%candesartan%'
        OR LOWER(drug) LIKE '%irbesartan%' OR LOWER(drug) LIKE '%olmesartan%' OR LOWER(drug) LIKE '%telmisartan%'
        OR LOWER(drug) LIKE '%sacubitril%' -- for ARNI combo
        THEN 'ACEi/ARB/ARNI'
      WHEN LOWER(drug) LIKE '%furosemide%' OR LOWER(drug) LIKE '%bumetanide%' 
        OR LOWER(drug) LIKE '%torsemide%' OR LOWER(drug) LIKE '%ethacrynic%'
        THEN 'Loop diuretic'
    END AS drug_class
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  WHERE pr.starttime IS NOT NULL
),

-- 3. First start per class per admission
first_class_start AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    p.drug_class,
    MIN(p.starttime) AS first_start
  FROM cohort c
  JOIN presc_classes p
    ON c.hadm_id = p.hadm_id
  WHERE p.drug_class IS NOT NULL
  GROUP BY c.subject_id, c.hadm_id, c.admittime, c.dischtime, p.drug_class
),

-- 4. Tag initiations in each window
init_flags AS (
  SELECT
    fc.drug_class,
    fc.hadm_id,
    -- Initiation = first_start in window and no earlier start before window
    CASE 
      WHEN fc.first_start BETWEEN fc.admittime AND DATETIME_ADD(fc.admittime, INTERVAL 48 HOUR)
      THEN 1 ELSE 0 END AS first48h_init,
    CASE 
      WHEN fc.first_start BETWEEN DATETIME_SUB(fc.dischtime, INTERVAL 24 HOUR) AND fc.dischtime
      THEN 1 ELSE 0 END AS final24h_init
  FROM first_class_start fc
),

-- 5. Aggregate counts & percentages
agg AS (
  SELECT
    drug_class,
    COUNT(DISTINCT CASE WHEN first48h_init = 1 THEN hadm_id END) AS n_first48h,
    COUNT(DISTINCT CASE WHEN final24h_init = 1 THEN hadm_id END) AS n_final24h,
    COUNT(DISTINCT hadm_id) AS cohort_size
  FROM init_flags
  GROUP BY drug_class
)

SELECT
  drug_class,
  cohort_size,
  n_first48h,
  ROUND(n_first48h*100.0/cohort_size,1) AS pct_first48h,
  n_final24h,
  ROUND(n_final24h*100.0/cohort_size,1) AS pct_final24h,
  ROUND((n_final24h*100.0/cohort_size) - (n_first48h*100.0/cohort_size),1) AS abs_diff_pp
FROM agg
ORDER BY drug_class;