WITH patient_admissions AS (
  SELECT DISTINCT
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
  WHERE p.gender = 'M'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 42 AND 52
),

diabetes_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses
  WHERE (
    (icd_version = 10 AND (icd_code LIKE 'E10%' OR icd_code LIKE 'E11%'))
  )
),

hf_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses
  WHERE (icd_version = 10 AND icd_code LIKE 'I50%')
),

patients_with_conditions AS (
  SELECT pa.subject_id, pa.hadm_id, pa.admittime, pa.dischtime
  FROM patient_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd diab
    ON pa.hadm_id = diab.hadm_id
  INNER JOIN diabetes_codes dc
    ON diab.icd_code = dc.icd_code
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd hf
    ON pa.hadm_id = hf.hadm_id
  INNER JOIN hf_codes hfc
    ON hf.icd_code = hfc.icd_code
  GROUP BY pa.subject_id, pa.hadm_id, pa.admittime, pa.dischtime
),

antidiabetic_classes AS (
  SELECT
    subject_id,
    hadm_id,
    starttime,
    stoptime,
    CASE
      WHEN LOWER(drug) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(drug) LIKE '%metformin%' THEN 'Metformin'
      WHEN LOWER(drug) IN ('glipizide', 'glyburide', 'glimepiride') 
        OR LOWER(drug) LIKE '%glipizide%' OR LOWER(drug) LIKE '%glyburide%' OR LOWER(drug) LIKE '%glimepiride%'
        THEN 'Sulfonylurea'
      WHEN LOWER(drug) IN ('sitagliptin', 'saxagliptin', 'linagliptin', 'alogliptin')
        OR LOWER(drug) LIKE '%sitagliptin%' OR LOWER(drug) LIKE '%saxagliptin%' OR LOWER(drug) LIKE '%linagliptin%' OR LOWER(drug) LIKE '%alogliptin%'
        THEN 'DPP-4'
      WHEN LOWER(drug) IN ('empagliflozin', 'dapagliflozin', 'canagliflozin')
        OR LOWER(drug) LIKE '%empagliflozin%' OR LOWER(drug) LIKE '%dapagliflozin%' OR LOWER(drug) LIKE '%canagliflozin%'
        THEN 'SGLT2'
      WHEN LOWER(drug) IN ('exenatide', 'liraglutide', 'semaglutide', 'dulaglutide')
        OR LOWER(drug) LIKE '%exenatide%' OR LOWER(drug) LIKE '%liraglutide%' OR LOWER(drug) LIKE '%semaglutide%' OR LOWER(drug) LIKE '%dulaglutide%'
        THEN 'GLP-1'
      WHEN LOWER(drug) IN ('pioglitazone', 'rosiglitazone')
        OR LOWER(drug) LIKE '%pioglitazone%' OR LOWER(drug) LIKE '%rosiglitazone%'
        THEN 'TZD'
      ELSE NULL
    END AS drug_class
  FROM `physionet-data.mimiciv_3_1_hosp`.prescriptions
  WHERE drug IS NOT NULL
    AND starttime IS NOT NULL
),

class_exposure AS (
  SELECT
    pwc.subject_id,
    adc.drug_class,
    MAX(CASE
      WHEN adc.starttime < pwc.admittime + INTERVAL '24' HOUR
        AND (adc.stoptime IS NULL OR adc.stoptime >= pwc.admittime)
        THEN 1 ELSE 0 END) AS in_first_24h,
    MAX(CASE
      WHEN adc.starttime < pwc.dischtime
        AND (adc.stoptime IS NULL OR adc.stoptime >= pwc.dischtime - INTERVAL '12' HOUR)
        THEN 1 ELSE 0 END) AS in_final_12h
  FROM patients_with_conditions pwc
  LEFT JOIN antidiabetic_classes adc
    ON pwc.subject_id = adc.subject_id AND pwc.hadm_id = adc.hadm_id
  WHERE adc.drug_class IS NOT NULL
  GROUP BY pwc.subject_id, adc.drug_class
),

summary AS (
  SELECT
    drug_class,
    AVG(in_first_24h) * 100 AS pct_first_24h,
    AVG(in_final_12h) * 100 AS pct_final_12h
  FROM class_exposure
  GROUP BY drug_class
)

SELECT
  drug_class,
  ROUND(pct_first_24h, 2) AS pct_first_24h,
  ROUND(pct_final_12h, 2) AS pct_final_12h,
  ROUND(pct_final_12h - pct_first_24h, 2) AS net_change_pp
FROM summary
ORDER BY drug_class;