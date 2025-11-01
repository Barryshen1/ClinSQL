WITH cohort AS (
  SELECT a.subject_id, a.hadm_id, p.gender, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  -- women aged 69–79
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 69 AND 79
),
dx AS (
  SELECT hadm_id,
         MAX(CASE WHEN ( (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^250[0-9]{1}[02]?$')) 
                        OR (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^E11')) )
                  THEN 1 ELSE 0 END) AS has_t2dm,
         MAX(CASE WHEN ( (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^428')) 
                        OR (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^I50')) )
                  THEN 1 ELSE 0 END) AS has_hf
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
cohort_filtered AS (
  SELECT c.subject_id, c.hadm_id
  FROM cohort c
  JOIN dx ON c.hadm_id = dx.hadm_id
  WHERE dx.has_t2dm = 1 AND dx.has_hf = 1
),
drug_flags AS (
  SELECT cf.hadm_id,
         CASE WHEN LOWER(pr.drug) LIKE '%insulin%' THEN 'insulin'
              WHEN LOWER(pr.drug) LIKE '%metformin%' THEN 'metformin'
              WHEN LOWER(pr.drug) LIKE '%glyburide%' 
                OR LOWER(pr.drug) LIKE '%glipizide%'
                OR LOWER(pr.drug) LIKE '%glimepiride%'
                OR LOWER(pr.drug) LIKE '%tolbutamide%'
                OR LOWER(pr.drug) LIKE '%chlorpropamide%' THEN 'sulfonylurea'
              WHEN LOWER(pr.drug) LIKE '%sitagliptin%'
                OR LOWER(pr.drug) LIKE '%saxagliptin%'
                OR LOWER(pr.drug) LIKE '%linagliptin%'
                OR LOWER(pr.drug) LIKE '%alogliptin%' THEN 'dpp4'
              WHEN LOWER(pr.drug) LIKE '%canagliflozin%'
                OR LOWER(pr.drug) LIKE '%dapagliflozin%'
                OR LOWER(pr.drug) LIKE '%empagliflozin%'
                OR LOWER(pr.drug) LIKE '%ertugliflozin%' THEN 'sglt2'
              WHEN LOWER(pr.drug) LIKE '%liraglutide%'
                OR LOWER(pr.drug) LIKE '%semaglutide%'
                OR LOWER(pr.drug) LIKE '%exenatide%'
                OR LOWER(pr.drug) LIKE '%dulaglutide%'
                OR LOWER(pr.drug) LIKE '%albiglutide%'
                OR LOWER(pr.drug) LIKE '%lixisenatide%' THEN 'glp1'
              WHEN LOWER(pr.drug) LIKE '%pioglitazone%'
                OR LOWER(pr.drug) LIKE '%rosiglitazone%' THEN 'tzd'
         END AS drug_class,
         CASE WHEN pr.starttime <= a.admittime + INTERVAL 72 HOUR THEN 1 ELSE 0 END AS in_first_72h,
         CASE WHEN pr.starttime >= a.dischtime - INTERVAL 72 HOUR THEN 1 ELSE 0 END AS in_last_72h
  FROM cohort_filtered cf
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON cf.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON cf.hadm_id = pr.hadm_id
  WHERE pr.starttime IS NOT NULL
),
flags_per_adm AS (
  SELECT hadm_id,
         drug_class,
         MAX(in_first_72h) AS first_flag,
         MAX(in_last_72h) AS last_flag
  FROM drug_flags
  WHERE drug_class IS NOT NULL
  GROUP BY hadm_id, drug_class
),
summary AS (
  SELECT drug_class,
         COUNTIF(first_flag = 1) AS num_first,
         COUNTIF(last_flag = 1)  AS num_last,
         COUNT(DISTINCT f.hadm_id) AS total
  FROM flags_per_adm f
  GROUP BY drug_class
)
SELECT drug_class,
       ROUND(100 * num_first / total, 1) AS pct_first_72h,
       ROUND(100 * num_last / total, 1)  AS pct_last_72h
FROM summary
ORDER BY drug_class;