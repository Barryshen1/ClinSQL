WITH cohort AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  -- age/gender filter
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 37 AND 47
    -- LOS filter: ensure ≥ 144h
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 144
    -- must have both diabetes and HF; filter later via EXISTS
),
dx AS (
  SELECT hadm_id,
         MAX(CASE WHEN (icd_version = 9 AND (icd_code LIKE '249%' OR icd_code LIKE '250%'))
                   OR (icd_version = 10 AND (icd_code LIKE 'E08%' OR icd_code LIKE 'E09%' OR icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' OR icd_code LIKE 'E13%'))
                  THEN 1 ELSE 0 END) AS has_dm,
         MAX(CASE WHEN (icd_version = 9 AND icd_code LIKE '428%')
                   OR (icd_version = 10 AND icd_code LIKE 'I50%')
                  THEN 1 ELSE 0 END) AS has_hf
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
cohort_with_dx AS (
  SELECT c.*
  FROM cohort c
  JOIN dx
    ON c.hadm_id = dx.hadm_id
  WHERE dx.has_dm = 1 AND dx.has_hf = 1
),
rx_classified AS (
  SELECT c.subject_id, c.hadm_id, c.admittime, c.dischtime,
         CASE 
           WHEN LOWER(drug) LIKE '%metformin%' 
             OR LOWER(drug) LIKE '%insulin%'
             OR LOWER(drug) LIKE '%glipizide%'
             OR LOWER(drug) LIKE '%glyburide%'
             OR LOWER(drug) LIKE '%pioglitazone%'
             OR LOWER(drug) LIKE '%sitagliptin%'
           THEN 'antidiabetic'
           WHEN LOWER(drug) LIKE '%metoprolol%' 
             OR LOWER(drug) LIKE '%atenolol%'
             OR LOWER(drug) LIKE '%propranolol%'
             OR LOWER(drug) LIKE '%carvedilol%'
           THEN 'beta_blocker'
           WHEN LOWER(drug) LIKE '%lisinopril%'
             OR LOWER(drug) LIKE '%enalapril%'
             OR LOWER(drug) LIKE '%ramipril%'
             OR LOWER(drug) LIKE '%losartan%'
             OR LOWER(drug) LIKE '%valsartan%'
             OR LOWER(drug) LIKE '%candesartan%'
             OR LOWER(drug) LIKE '%sacubitril/valsartan%'
           THEN 'acei_arb_arni'
           WHEN LOWER(drug) LIKE '%furosemide%'
             OR LOWER(drug) LIKE '%bumetanide%'
             OR LOWER(drug) LIKE '%torsemide%'
           THEN 'loop_diuretic'
         END AS drug_class,
         pr.starttime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN cohort_with_dx c
    ON pr.hadm_id = c.hadm_id
  WHERE LOWER(drug) IS NOT NULL
),
rx_flags AS (
  SELECT subject_id, hadm_id, drug_class,
         MAX(CASE WHEN drug_class IS NOT NULL 
                   AND starttime < TIMESTAMP_ADD(admittime, INTERVAL 72 HOUR)
                  THEN 1 ELSE 0 END) AS first72h,
         MAX(CASE WHEN drug_class IS NOT NULL 
                   AND starttime >= TIMESTAMP_SUB(dischtime, INTERVAL 72 HOUR)
                  THEN 1 ELSE 0 END) AS last72h
  FROM rx_classified
  WHERE drug_class IS NOT NULL
  GROUP BY subject_id, hadm_id, drug_class
),
rx_transitions AS (
  SELECT drug_class,
         COUNT(*) AS n_patients,
         COUNTIF(first72h=1 AND last72h=1) AS continued,
         COUNTIF(first72h=0 AND last72h=1) AS initiated,
         COUNTIF(first72h=1 AND last72h=0) AS discontinued
  FROM rx_flags
  GROUP BY drug_class
),
cohort_count AS (
  SELECT COUNT(DISTINCT hadm_id) AS total_patients
  FROM cohort_with_dx
)
SELECT t.drug_class,
       t.n_patients,
       ROUND(100.0*t.n_patients/co.total_patients,1) AS pct_any,
       t.continued,
       ROUND(100.0*t.continued/co.total_patients,1) AS pct_continued,
       t.initiated,
       ROUND(100.0*t.initiated/co.total_patients,1) AS pct_initiated,
       t.discontinued,
       ROUND(100.0*t.discontinued/co.total_patients,1) AS pct_discontinued
FROM rx_transitions t
CROSS JOIN cohort_count co
ORDER BY drug_class;