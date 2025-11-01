WITH cohort AS (
  -- Select male patients age 36-46 with T2DM and HF
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    -- T2DM
    JOIN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE
        (
          (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^250[.]0|^250[.]2|^250[.]4|^250[.]6|^250[.]8')) -- T2DM ICD-9
          OR
          (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^E11')) -- T2DM ICD-10
        )
      GROUP BY hadm_id
    ) t2dm ON a.hadm_id = t2dm.hadm_id
    -- HF
    JOIN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE
        (
          (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^428'))
          OR
          (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^I50'))
        )
      GROUP BY hadm_id
    ) hf ON a.hadm_id = hf.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 36 AND 46
    AND DATETIME_DIFF(a.dischtime, a.admittime, HOUR) >= 48 -- Only admissions >=48h
),

drug_classes AS (
  -- Map drugs to antidiabetic classes
  SELECT
    'Insulin' AS drug_class, r.drug
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` r
  WHERE LOWER(r.drug) LIKE '%insulin%'
  UNION ALL
  SELECT 'Metformin', r.drug
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` r
  WHERE LOWER(r.drug) LIKE '%metformin%'
  UNION ALL
  SELECT 'Sulfonylurea', r.drug
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` r
  WHERE LOWER(r.drug) LIKE '%glyburide%' OR LOWER(r.drug) LIKE '%glipizide%' OR LOWER(r.drug) LIKE '%glimepiride%'
  UNION ALL
  SELECT 'DPP-4', r.drug
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` r
  WHERE LOWER(r.drug) LIKE '%sitagliptin%' OR LOWER(r.drug) LIKE '%linagliptin%' OR LOWER(r.drug) LIKE '%saxagliptin%' OR LOWER(r.drug) LIKE '%alogliptin%'
  UNION ALL
  SELECT 'GLP-1', r.drug
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` r
  WHERE LOWER(r.drug) LIKE '%liraglutide%' OR LOWER(r.drug) LIKE '%exenatide%' OR LOWER(r.drug) LIKE '%dulaglutide%' OR LOWER(r.drug) LIKE '%semaglutide%'
  UNION ALL
  SELECT 'SGLT2', r.drug
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` r
  WHERE LOWER(r.drug) LIKE '%canagliflozin%' OR LOWER(r.drug) LIKE '%dapagliflozin%' OR LOWER(r.drug) LIKE '%empagliflozin%'
  UNION ALL
  SELECT 'TZD', r.drug
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` r
  WHERE LOWER(r.drug) LIKE '%pioglitazone%' OR LOWER(r.drug) LIKE '%rosiglitazone%'
  UNION ALL
  SELECT 'Meglitinide', r.drug
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` r
  WHERE LOWER(r.drug) LIKE '%repaglinide%' OR LOWER(r.drug) LIKE '%nateglinide%'
),

first_initiation AS (
  -- For each admission and drug class, find first prescription time
  SELECT
    c.subject_id,
    c.hadm_id,
    dc.drug_class,
    MIN(r.starttime) AS first_presc_time,
    c.admittime,
    c.dischtime
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` r
    ON c.hadm_id = r.hadm_id
  JOIN drug_classes dc
    ON LOWER(r.drug) = LOWER(dc.drug)
  GROUP BY c.subject_id, c.hadm_id, dc.drug_class, c.admittime, c.dischtime
),

initiation_flags AS (
  -- Flag initiations in first 12h and final 48h
  SELECT
    drug_class,
    subject_id,
    hadm_id,
    CASE
      WHEN DATETIME_DIFF(first_presc_time, admittime, HOUR) BETWEEN 0 AND 12 THEN 1 ELSE 0
    END AS first_12h_flag,
    CASE
      WHEN DATETIME_DIFF(dischtime, first_presc_time, HOUR) BETWEEN 0 AND 48 THEN 1 ELSE 0
    END AS final_48h_flag
  FROM first_initiation
)

SELECT
  drug_class,
  ROUND(SUM(first_12h_flag) / COUNT(DISTINCT hadm_id) * 100, 2) AS first_12h_initiation_rate_pct,
  ROUND(SUM(final_48h_flag) / COUNT(DISTINCT hadm_id) * 100, 2) AS final_48h_initiation_rate_pct,
  ROUND(
    (SUM(final_48h_flag) / COUNT(DISTINCT hadm_id) * 100)
    - (SUM(first_12h_flag) / COUNT(DISTINCT hadm_id) * 100)
  , 2) AS net_change_pp
FROM initiation_flags
GROUP BY drug_class
ORDER BY drug_class;