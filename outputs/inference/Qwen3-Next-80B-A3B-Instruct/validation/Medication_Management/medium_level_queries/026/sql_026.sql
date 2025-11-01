WITH eligible_admissions AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.patients p ON a.subject_id = p.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d1 ON a.subject_id = d1.subject_id AND a.hadm_id = d1.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d1_desc ON d1.icd_code = d1_desc.icd_code AND d1.icd_version = d1_desc.icd_version
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d2 ON a.subject_id = d2.subject_id AND a.hadm_id = d2.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d2_desc ON d2.icd_code = d2_desc.icd_code AND d2.icd_version = d2_desc.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
    AND (
      (d1_desc.long_title LIKE '%Type 2 diabetes mellitus%' AND d2_desc.long_title LIKE '%heart failure%')
      OR
      (d2_desc.long_title LIKE '%Type 2 diabetes mellitus%' AND d1_desc.long_title LIKE '%heart failure%')
    )
),

prescriptions_with_class AS (
  SELECT 
    p.subject_id,
    p.hadm_id,
    p.starttime,
    CASE 
      WHEN LOWER(p.drug) LIKE '%insulin%' THEN 'insulin'
      WHEN LOWER(p.drug) IN (
        'metformin', 'glimepiride', 'glipizide', 'glyburide', 'sitagliptin', 
        'saxagliptin', 'linagliptin', 'empagliflozin', 'canagliflozin', 'dapagliflozin',
        'pioglitazone', 'rosiglitazone', 'repaglinide', 'nateglinide', 'chlorpropamide',
        'tolbutamide', 'acetohexamide', 'ertugliflozin', 'liraglutide',
        'semaglutide', 'exenatide', 'lixisenatide', 'albiglutide', 'dulaglutide'
      ) THEN 'oral_agent'
      ELSE NULL
    END AS drug_class
  FROM physionet-data.mimiciv_3_1_hosp.prescriptions p
  JOIN eligible_admissions ea ON p.subject_id = ea.subject_id AND p.hadm_id = ea.hadm_id
  WHERE p.starttime >= ea.admittime AND p.starttime <= ea.dischtime
    AND (
      LOWER(p.drug) LIKE '%insulin%'
      OR LOWER(p.drug) IN (
        'metformin', 'glimepiride', 'glipizide', 'glyburide', 'sitagliptin', 
        'saxagliptin', 'linagliptin', 'empagliflozin', 'canagliflozin', 'dapagliflozin',
        'pioglitazone', 'rosiglitazone', 'repaglinide', 'nateglinide', 'chlorpropamide',
        'tolbutamide', 'acetohexamide', 'ertugliflozin', 'liraglutide',
        'semaglutide', 'exenatide', 'lixisenatide', 'albiglutide', 'dulaglutide'
      )
    )
),

first_72h AS (
  SELECT 
    ea.subject_id,
    ea.hadm_id,
    MAX(CASE WHEN pwc.drug_class = 'insulin' THEN 1 ELSE 0 END) AS insulin_first_72h,
    MAX(CASE WHEN pwc.drug_class = 'oral_agent' THEN 1 ELSE 0 END) AS oral_agent_first_72h
  FROM eligible_admissions ea
  LEFT JOIN prescriptions_with_class pwc 
    ON ea.subject_id = pwc.subject_id 
    AND ea.hadm_id = pwc.hadm_id 
    AND pwc.starttime BETWEEN ea.admittime AND TIMESTAMP_ADD(ea.admittime, INTERVAL 72 HOUR)
  GROUP BY ea.subject_id, ea.hadm_id
),

final_72h AS (
  SELECT 
    ea.subject_id,
    ea.hadm_id,
    MAX(CASE WHEN pwc.drug_class = 'insulin' THEN 1 ELSE 0 END) AS insulin_final_72h,
    MAX(CASE WHEN pwc.drug_class = 'oral_agent' THEN 1 ELSE 0 END) AS oral_agent_final_72h
  FROM eligible_admissions ea
  LEFT JOIN prescriptions_with_class pwc 
    ON ea.subject_id = pwc.subject_id 
    AND ea.hadm_id = pwc.hadm_id 
    AND pwc.starttime BETWEEN TIMESTAMP_SUB(ea.dischtime, INTERVAL 72 HOUR) AND ea.dischtime
  GROUP BY ea.subject_id, ea.hadm_id
)

SELECT 
  ROUND(100.0 * COUNTIF(f.insulin_first_72h = 1) / NULLIF(COUNTIF(f.insulin_first_72h = 1 OR f.oral_agent_first_72h = 1), 0), 2) AS pct_insulin_first_72h,
  ROUND(100.0 * COUNTIF(f.oral_agent_first_72h = 1) / NULLIF(COUNTIF(f.insulin_first_72h = 1 OR f.oral_agent_first_72h = 1), 0), 2) AS pct_oral_agent_first_72h,
  ROUND(100.0 * COUNTIF(fn.insulin_final_72h = 1) / NULLIF(COUNTIF(fn.insulin_final_72h = 1 OR fn.oral_agent_final_72h = 1), 0), 2) AS pct_insulin_final_72h,
  ROUND(100.0 * COUNTIF(fn.oral_agent_final_72h = 1) / NULLIF(COUNTIF(fn.insulin_final_72h = 1 OR fn.oral_agent_final_72h = 1), 0), 2) AS pct_oral_agent_final_72h
FROM first_72h f
JOIN final_72h fn ON f.subject_id = fn.subject_id AND f.hadm_id = fn.hadm_id;