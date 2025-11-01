WITH eligible_patients AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE
    p.anchor_age BETWEEN 71 AND 81
    AND p.gender = 'M'
    AND a.hospital_expire_flag = 0
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND DATETIME_DIFF(a.dischtime, a.admittime, HOUR) >= 72
),

diabetes_admits AS (
  SELECT DISTINCT
    ep.hadm_id
  FROM
    eligible_patients ep
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON ep.hadm_id = d.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%diabetes%'
),

heart_failure_admits AS (
  SELECT DISTINCT
    ep.hadm_id
  FROM
    eligible_patients ep
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON ep.hadm_id = d.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%heart failure%'
    AND LOWER(dd.long_title) LIKE '%acute%'
),

target_admits AS (
  SELECT ep.*
  FROM eligible_patients ep
  JOIN diabetes_admits da ON ep.hadm_id = da.hadm_id
  JOIN heart_failure_admits hfa ON ep.hadm_id = hfa.hadm_id
),

drug_mappings AS (
  SELECT
    hadm_id,
    starttime,
    stoptime,
    LOWER(drug) AS drug_name,
    CASE
      WHEN LOWER(drug) LIKE '%metformin%' THEN 'Metformin'
      WHEN LOWER(drug) LIKE '%glipizide%' OR LOWER(drug) LIKE '%glyburide%' OR LOWER(drug) LIKE '%glimepiride%' THEN 'Sulfonylureas'
      WHEN LOWER(drug) LIKE '%sitagliptin%' OR LOWER(drug) LIKE '%saxagliptin%' OR LOWER(drug) LIKE '%linagliptin%' THEN 'DPP-4'
      WHEN LOWER(drug) LIKE '%empagliflozin%' OR LOWER(drug) LIKE '%dapagliflozin%' OR LOWER(drug) LIKE '%canagliflozin%' THEN 'SGLT2'
      WHEN LOWER(drug) LIKE '%pioglitazone%' OR LOWER(drug) LIKE '%rosiglitazone%' THEN 'Thiazolidinediones'
      ELSE NULL
    END AS drug_class
  FROM
    physionet-data.mimiciv_3_1_hosp.prescriptions
  WHERE
    LOWER(drug) LIKE '%metformin%'
    OR LOWER(drug) LIKE '%glipizide%'
    OR LOWER(drug) LIKE '%glyburide%'
    OR LOWER(drug) LIKE '%glimepiride%'
    OR LOWER(drug) LIKE '%sitagliptin%'
    OR LOWER(drug) LIKE '%saxagliptin%'
    OR LOWER(drug) LIKE '%linagliptin%'
    OR LOWER(drug) LIKE '%empagliflozin%'
    OR LOWER(drug) LIKE '%dapagliflozin%'
    OR LOWER(drug) LIKE '%canagliflozin%'
    OR LOWER(drug) LIKE '%pioglitazone%'
    OR LOWER(drug) LIKE '%rosiglitazone%'
),

initiations AS (
  SELECT
    dm.hadm_id,
    dm.drug_class,
    dm.starttime,
    ta.admittime,
    ta.dischtime,
    CASE
      WHEN dm.starttime >= ta.admittime AND dm.starttime <= DATETIME_ADD(ta.admittime, INTERVAL 72 HOUR) THEN 1
      ELSE 0
    END AS initiated_first_72h,
    CASE
      WHEN dm.starttime >= DATETIME_SUB(ta.dischtime, INTERVAL 48 HOUR) AND dm.starttime <= ta.dischtime THEN 1
      ELSE 0
    END AS initiated_last_48h
  FROM
    drug_mappings dm
  JOIN
    target_admits ta
    ON dm.hadm_id = ta.hadm_id
  WHERE
    dm.drug_class IS NOT NULL
),

patient_drug_flags AS (
  SELECT
    hadm_id,
    drug_class,
    MAX(initiated_first_72h) AS first_72h_flag,
    MAX(initiated_last_48h) AS last_48h_flag
  FROM
    initiations
  GROUP BY
    hadm_id, drug_class
),

drug_summary AS (
  SELECT
    drug_class,
    COUNT(DISTINCT hadm_id) AS total_eligible,
    SUM(first_72h_flag) AS initiated_first_72h,
    SUM(last_48h_flag) AS initiated_last_48h
  FROM
    patient_drug_flags
  GROUP BY
    drug_class
)

SELECT
  drug_class,
  total_eligible,
  initiated_first_72h,
  initiated_last_48h,
  ROUND(SAFE_DIVIDE(initiated_first_72h, total_eligible) * 100, 2) AS first_72h_rate_pct,
  ROUND(SAFE_DIVIDE(initiated_last_48h, total_eligible) * 100, 2) AS last_48h_rate_pct
FROM
  drug_summary
ORDER BY
  drug_class;