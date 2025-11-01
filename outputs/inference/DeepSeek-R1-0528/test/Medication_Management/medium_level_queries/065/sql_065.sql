WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime,
    -- Calculate age at admission
    pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    -- Age 77-87 at admission
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 77 AND 87
    -- Admission ≥5 days (120 hours)
    AND DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) >= 120
),
diabetes AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code LIKE '250%') OR 
    (icd_version = 10 AND icd_code LIKE 'E1%')
),
heart_failure AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code LIKE '428%') OR 
    (icd_version = 10 AND icd_code LIKE 'I50%')
),
filtered_cohort AS (
  SELECT c.*
  FROM cohort c
  INNER JOIN diabetes d ON c.hadm_id = d.hadm_id
  INNER JOIN heart_failure hf ON c.hadm_id = hf.hadm_id
),
med_flags AS (
  SELECT 
    fc.hadm_id,
    -- Insulin: Initiation in 0-48h
    MAX(CASE 
          WHEN LOWER(p.drug) LIKE '%insulin%' 
          AND p.starttime BETWEEN fc.admittime AND DATETIME_ADD(fc.admittime, INTERVAL 48 HOUR) 
          THEN 1 ELSE 0 
        END) AS insulin_init_0_48h,
    -- Insulin: Active in final 72h
    MAX(CASE 
          WHEN LOWER(p.drug) LIKE '%insulin%' 
          AND p.starttime <= fc.dischtime 
          AND COALESCE(p.stoptime, fc.dischtime) >= DATETIME_SUB(fc.dischtime, INTERVAL 72 HOUR) 
          THEN 1 ELSE 0 
        END) AS insulin_final_72h,
    -- Oral Agents: Initiation in 0-48h
    MAX(CASE 
          WHEN LOWER(p.drug) LIKE ANY (
            '%metformin%', '%glipizide%', '%glyburide%', '%glimepiride%', 
            '%pioglitazone%', '%rosiglitazone%', '%sitagliptin%', '%saxagliptin%', 
            '%linagliptin%', '%alogliptin%', '%canagliflozin%', '%dapagliflozin%', 
            '%empagliflozin%', '%acarbose%', '%miglitol%', '%repaglinide%', '%nateglinide%'
          )
          AND p.starttime BETWEEN fc.admittime AND DATETIME_ADD(fc.admittime, INTERVAL 48 HOUR) 
          THEN 1 ELSE 0 
        END) AS oral_init_0_48h,
    -- Oral Agents: Active in final 72h
    MAX(CASE 
          WHEN LOWER(p.drug) LIKE ANY (
            '%metformin%', '%glipizide%', '%glyburide%', '%glimepiride%', 
            '%pioglitazone%', '%rosiglitazone%', '%sitagliptin%', '%saxagliptin%', 
            '%linagliptin%', '%alogliptin%', '%canagliflozin%', '%dapagliflozin%', 
            '%empagliflozin%', '%acarbose%', '%miglitol%', '%repaglinide%', '%nateglinide%'
          )
          AND p.starttime <= fc.dischtime 
          AND COALESCE(p.stoptime, fc.dischtime) >= DATETIME_SUB(fc.dischtime, INTERVAL 72 HOUR) 
          THEN 1 ELSE 0 
        END) AS oral_final_72h
  FROM filtered_cohort fc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON fc.hadm_id = p.hadm_id
  GROUP BY fc.hadm_id
)
SELECT 
  'Insulin' AS medication_class,
  AVG(insulin_init_0_48h) AS initiation_rate_0_48h,
  AVG(insulin_final_72h) AS prevalence_final_72h,
  AVG(insulin_final_72h) - AVG(insulin_init_0_48h) AS net_change_pp
FROM med_flags
UNION ALL
SELECT 
  'Oral Agents' AS medication_class,
  AVG(oral_init_0_48h) AS initiation_rate_0_48h,
  AVG(oral_final_72h) AS prevalence_final_72h,
  AVG(oral_final_72h) - AVG(oral_init_0_48h) AS net_change_pp
FROM med_flags;