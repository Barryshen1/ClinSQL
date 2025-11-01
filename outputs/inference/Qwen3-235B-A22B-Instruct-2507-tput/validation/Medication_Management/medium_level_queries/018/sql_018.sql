WITH patient_admissions AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    p.anchor_year,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 81 AND 91
),

t2dm_hf_admissions AS (
  SELECT pa.subject_id, pa.hadm_id, pa.admittime, pa.dischtime
  FROM patient_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di1
    ON pa.hadm_id = di1.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d1
    ON di1.icd_code = d1.icd_code AND di1.icd_version = d1.icd_version
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di2
    ON pa.hadm_id = di2.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d2
    ON di2.icd_code = d2.icd_code AND di2.icd_version = d2.icd_version
  WHERE (d1.icd_code LIKE 'E11%' AND d1.icd_version = 10)
    AND (d2.icd_code LIKE 'I50%' AND d2.icd_version = 10)
  GROUP BY pa.subject_id, pa.hadm_id, pa.admittime, pa.dischtime
),

drug_exposure AS (
  SELECT 
    th.hadm_id,
    th.admittime,
    th.dischtime,
    LOWER(pres.drug) AS drug_name,
    pres.starttime,
    COALESCE(pres.stoptime, pres.starttime) AS stoptime,
    CASE
      WHEN LOWER(pres.drug) LIKE '%metformin%' THEN 'metformin'
      WHEN LOWER(pres.drug) IN ('glipizide', 'glyburide', 'glimepiride') 
        OR LOWER(pres.drug) LIKE '%glipizide%' 
        OR LOWER(pres.drug) LIKE '%glyburide%' 
        OR LOWER(pres.drug) LIKE '%glimepiride%' THEN 'sulfonylurea'
      WHEN LOWER(pres.drug) IN ('sitagliptin', 'saxagliptin', 'linagliptin')
        OR LOWER(pres.drug) LIKE '%sitagliptin%'
        OR LOWER(pres.drug) LIKE '%saxagliptin%'
        OR LOWER(pres.drug) LIKE '%linagliptin%' THEN 'DPP4'
      WHEN LOWER(pres.drug) IN ('empagliflozin', 'dapagliflozin', 'canagliflozin')
        OR LOWER(pres.drug) LIKE '%empagliflozin%'
        OR LOWER(pres.drug) LIKE '%dapagliflozin%'
        OR LOWER(pres.drug) LIKE '%canagliflozin%' THEN 'SGLT2'
      WHEN LOWER(pres.drug) IN ('pioglitazone', 'rosiglitazone')
        OR LOWER(pres.drug) LIKE '%pioglitazone%'
        OR LOWER(pres.drug) LIKE '%rosiglitazone%' THEN 'TZD'
      ELSE NULL
    END AS drug_class
  FROM t2dm_hf_admissions th
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.prescriptions pres
    ON th.hadm_id = pres.hadm_id
  WHERE pres.starttime IS NOT NULL
    AND (
      LOWER(pres.drug) LIKE '%metformin%' OR
      LOWER(pres.drug) LIKE '%glipizide%' OR LOWER(pres.drug) LIKE '%glyburide%' OR LOWER(pres.drug) LIKE '%glimepiride%' OR
      LOWER(pres.drug) LIKE '%sitagliptin%' OR LOWER(pres.drug) LIKE '%saxagliptin%' OR LOWER(pres.drug) LIKE '%linagliptin%' OR
      LOWER(pres.drug) LIKE '%empagliflozin%' OR LOWER(pres.drug) LIKE '%dapagliflozin%' OR LOWER(pres.drug) LIKE '%canagliflozin%' OR
      LOWER(pres.drug) LIKE '%pioglitazone%' OR LOWER(pres.drug) LIKE '%rosiglitazone%'
    )
),

exposure_windows AS (
  SELECT 
    drug_class,
    MAX(CASE 
      WHEN starttime <= DATETIME_ADD(admittime, INTERVAL 72 HOUR) 
      THEN 1 ELSE 0 END) AS in_initial_period,
    MAX(CASE 
      WHEN stoptime >= DATETIME_ADD(dischtime, INTERVAL -48 HOUR)
       AND starttime <= dischtime
      THEN 1 ELSE 0 END) AS in_final_period
  FROM drug_exposure
  WHERE drug_class IS NOT NULL
  GROUP BY drug_class, hadm_id
),

class_summary AS (
  SELECT 
    drug_class,
    AVG(in_initial_period) * 100 AS initial_prevalence,
    AVG(in_final_period) * 100 AS final_prevalence
  FROM exposure_windows
  GROUP BY drug_class
)

SELECT 
  drug_class,
  ROUND(initial_prevalence, 2) AS initial_prevalence_pct,
  ROUND(final_prevalence, 2) AS final_prevalence_pct,
  ROUND(final_prevalence - initial_prevalence, 2) AS absolute_difference_pct
FROM class_summary
ORDER BY drug_class;