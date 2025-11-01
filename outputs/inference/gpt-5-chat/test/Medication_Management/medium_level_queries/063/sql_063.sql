WITH cohort AS (
  -- male inpatients age 45-55 with both DM and HF
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
),
dx_dm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE ( (icd_version = 9 AND icd_code LIKE '250%')
       OR (icd_version = 10 AND icd_code LIKE 'E10%')
       OR (icd_version = 10 AND icd_code LIKE 'E11%')
       OR (icd_version = 10 AND icd_code LIKE 'E13%') )
),
dx_hf AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE ( (icd_version = 9 AND icd_code LIKE '428%')
       OR (icd_version = 10 AND icd_code LIKE 'I50%') )
),
cohort_dx AS (
  SELECT c.*
  FROM cohort c
  JOIN dx_dm dm ON c.hadm_id = dm.hadm_id
  JOIN dx_hf hf ON c.hadm_id = hf.hadm_id
),
med_class AS (
  SELECT 
    hadm_id,
    CASE 
      WHEN UPPER(drug) LIKE '%INSULIN%' THEN 'insulin'
      WHEN UPPER(drug) LIKE '%METFORMIN%' 
        OR UPPER(drug) LIKE '%GLIPIZIDE%'
        OR UPPER(drug) LIKE '%GLYBURIDE%'
        OR UPPER(drug) LIKE '%PIOGLITAZONE%'
        OR UPPER(drug) LIKE '%SITAGLIPTIN%'
        OR UPPER(drug) LIKE '%LINAGLIPTIN%'
        OR UPPER(drug) LIKE '%ALOGIPTIN%'
        OR UPPER(drug) LIKE '%GLIMEPIRIDE%'
        OR UPPER(drug) LIKE '%NATEGLINIDE%'
        OR UPPER(drug) LIKE '%REPAGLINIDE%'
        OR UPPER(drug) LIKE '%ACARBOSE%'
        OR UPPER(drug) LIKE '%CANAGLIFLOZIN%'
        OR UPPER(drug) LIKE '%DAPAGLIFLOZIN%'
        OR UPPER(drug) LIKE '%EMPAGLIFLOZIN%'
      THEN 'oral_antidiabetic'
      ELSE NULL
    END AS drug_cat,
    starttime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
),
med_in_windows AS (
  SELECT
    cd.hadm_id,
    mc.drug_cat,
    CASE 
      WHEN mc.starttime BETWEEN cd.admittime 
           AND DATETIME_ADD(cd.admittime, INTERVAL 12 HOUR)
      THEN 'first12h'
      WHEN mc.starttime BETWEEN DATETIME_SUB(cd.dischtime, INTERVAL 72 HOUR) 
           AND cd.dischtime
      THEN 'final72h'
      ELSE NULL
    END AS time_window
  FROM cohort_dx cd
  JOIN med_class mc
    ON cd.hadm_id = mc.hadm_id
  WHERE mc.drug_cat IS NOT NULL
),
adm_flag AS (
  -- flag each hadm for initiation in given window/drug_cat
  SELECT hadm_id, drug_cat, time_window
  FROM med_in_windows
  WHERE time_window IS NOT NULL
  GROUP BY hadm_id, drug_cat, time_window
),
stats AS (
  SELECT
    f.drug_cat,
    f.time_window,
    COUNT(DISTINCT f.hadm_id) AS n_init,
    COUNT(DISTINCT cd.hadm_id) AS n_total,
    SAFE_DIVIDE(COUNT(DISTINCT f.hadm_id), COUNT(DISTINCT cd.hadm_id)) * 100 AS pct_init
  FROM cohort_dx cd
  LEFT JOIN adm_flag f
    ON cd.hadm_id = f.hadm_id
  GROUP BY f.drug_cat, f.time_window
)
SELECT 
  drug_cat,
  MAX(CASE WHEN time_window = 'first12h' THEN pct_init END) AS pct_first12h,
  MAX(CASE WHEN time_window = 'final72h' THEN pct_init END) AS pct_final72h,
  MAX(CASE WHEN time_window = 'first12h' THEN pct_init END)
   - MAX(CASE WHEN time_window = 'final72h' THEN pct_init END) AS pp_diff_first_minus_final
FROM stats
GROUP BY drug_cat
ORDER BY drug_cat;