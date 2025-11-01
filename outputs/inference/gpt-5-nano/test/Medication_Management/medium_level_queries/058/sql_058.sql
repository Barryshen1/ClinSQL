WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 36 AND 46
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
t2dm_hadm AS (
  SELECT DISTINCT c.hadm_id
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON di.subject_id = c.subject_id AND di.hadm_id = c.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%type 2 diabetes%'
     OR LOWER(dd.long_title) LIKE '%diabetes mellitus type 2%'
     OR di.icd_code LIKE 'E11%'
),
hf_hadm AS (
  SELECT DISTINCT c.hadm_id
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON di.subject_id = c.subject_id AND di.hadm_id = c.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%heart failure%'
     OR LOWER(dd.long_title) LIKE '%congestive heart failure%'
     OR di.icd_code LIKE 'I50%'
),
cohort_final AS (
  SELECT c.subject_id, c.hadm_id, c.admittime, c.dischtime
  FROM cohort c
  JOIN t2dm_hadm t ON c.hadm_id = t.hadm_id
  JOIN hf_hadm h ON c.hadm_id = h.hadm_id
),
class_list AS (
  SELECT 'Insulin' AS antidiab_class
  UNION ALL SELECT 'Biguanide'
  UNION ALL SELECT 'Sulfonylurea'
  UNION ALL SELECT 'DPP-4 inhibitor'
  UNION ALL SELECT 'SGLT2 inhibitor'
  UNION ALL SELECT 'GLP-1 RA'
  UNION ALL SELECT 'TZD'
),
flags AS (
  SELECT cf.hadm_id,
         cl.antidiab_class,
         MAX(CASE WHEN p_init.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS init_present,
         MAX(CASE WHEN p_final.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS final_present
  FROM cohort_final cf
  CROSS JOIN class_list cl
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p_init
    ON p_init.hadm_id = cf.hadm_id
   AND p_init.starttime >= cf.admittime
   AND p_init.starttime < cf.admittime + INTERVAL 12 HOUR
   AND CASE
        WHEN LOWER(p_init.drug) LIKE '%insulin%' THEN 'Insulin'
        WHEN LOWER(p_init.drug) LIKE '%metformin%' OR LOWER(p_init.drug) LIKE '%glucophage%' THEN 'Biguanide'
        WHEN LOWER(p_init.drug) LIKE '%glyburide%' OR LOWER(p_init.drug) LIKE '%glipizide%' OR LOWER(p_init.drug) LIKE '%glimepiride%' THEN 'Sulfonylurea'
        WHEN LOWER(p_init.drug) LIKE '%sitagliptin%' OR LOWER(p_init.drug) LIKE '%linagliptin%' OR LOWER(p_init.drug) LIKE '%saxagliptin%' OR LOWER(p_init.drug) LIKE '%alogliptin%' THEN 'DPP-4 inhibitor'
        WHEN LOWER(p_init.drug) LIKE '%dapagliflozin%' OR LOWER(p_init.drug) LIKE '%empagliflozin%' OR LOWER(p_init.drug) LIKE '%canagliflozin%' OR LOWER(p_init.drug) LIKE '%ertugliflozin%' THEN 'SGLT2 inhibitor'
        WHEN LOWER(p_init.drug) LIKE '%liraglutide%' OR LOWER(p_init.drug) LIKE '%exenatide%' OR LOWER(p_init.drug) LIKE '%dulaglutide%' OR LOWER(p_init.drug) LIKE '%semaglutide%' THEN 'GLP-1 RA'
        WHEN LOWER(p_init.drug) LIKE '%pioglitazone%' OR LOWER(p_init.drug) LIKE '%rosiglitazone%' THEN 'TZD'
        ELSE NULL
      END = cl.antidiab_class
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p_final
    ON p_final.hadm_id = cf.hadm_id
   AND p_final.starttime >= cf.dischtime - INTERVAL 48 HOUR
   AND p_final.starttime < cf.dischtime
   AND CASE
        WHEN LOWER(p_final.drug) LIKE '%insulin%' THEN 'Insulin'
        WHEN LOWER(p_final.drug) LIKE '%metformin%' OR LOWER(p_final.drug) LIKE '%glucophage%' THEN 'Biguanide'
        WHEN LOWER(p_final.drug) LIKE '%glyburide%' OR LOWER(p_final.drug) LIKE '%glipizide%' OR LOWER(p_final.drug) LIKE '%glimepiride%' THEN 'Sulfonylurea'
        WHEN LOWER(p_final.drug) LIKE '%sitagliptin%' OR LOWER(p_final.drug) LIKE '%linagliptin%' OR LOWER(p_final.drug) LIKE '%saxagliptin%' OR LOWER(p_final.drug) LIKE '%alogliptin%' THEN 'DPP-4 inhibitor'
        WHEN LOWER(p_final.drug) LIKE '%dapagliflozin%' OR LOWER(p_final.drug) LIKE '%empagliflozin%' OR LOWER(p_final.drug) LIKE '%canagliflozin%' OR LOWER(p_final.drug) LIKE '%ertugliflozin%' THEN 'SGLT2 inhibitor'
        WHEN LOWER(p_final.drug) LIKE '%liraglutide%' OR LOWER(p_final.drug) LIKE '%exenatide%' OR LOWER(p_final.drug) LIKE '%dulaglutide%' OR LOWER(p_final.drug) LIKE '%semaglutide%' THEN 'GLP-1 RA'
        WHEN LOWER(p_final.drug) LIKE '%pioglitazone%' OR LOWER(p_final.drug) LIKE '%rosiglitazone%' THEN 'TZD'
        ELSE NULL
      END = cl.antidiab_class
  GROUP BY cf.hadm_id, cl.antidiab_class
)
-- Final: rates by class and time window (init vs final) with net change (percentage points)
SELECT
  antidiab_class,
  ROUND(100.0 * SUM(init_present) / NULLIF(COUNT(*), 0), 2) AS init_rate_percent,
  ROUND(100.0 * SUM(final_present) / NULLIF(COUNT(*), 0), 2) AS final_rate_percent,
  ROUND((SUM(final_present) - SUM(init_present)) * 100.0 / NULLIF(COUNT(*), 0), 2) AS net_change_pp
FROM flags
GROUP BY antidiab_class
ORDER BY antidiab_class;