WITH target_admissions AS (
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
    p.gender = 'M'
    AND p.anchor_age BETWEEN 64 AND 74
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
      JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d
        ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
      WHERE
        (d.icd_version = 9 AND di.icd_code LIKE '250%')
        OR (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^E0[8-9]|^E1[0-3]'))
    )
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
      JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d
        ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
      WHERE
        (d.icd_version = 9 AND di.icd_code = '4280')
        OR (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^I50\.(2[0-3]|3[0-3]|4[0-3])'))
    )
),

drug_classifications AS (
  SELECT
    subject_id,
    hadm_id,
    starttime,
    LOWER(drug) AS drug,
    CASE
      WHEN REGEXP_CONTAINS(LOWER(drug), r'insulin') THEN 'Insulin'
      WHEN REGEXP_CONTAINS(LOWER(drug), r'metformin') THEN 'Metformin'
      WHEN REGEXP_CONTAINS(LOWER(drug), r'glipizide|glyburide|glimepiride') THEN 'Sulfonylureas'
      WHEN REGEXP_CONTAINS(LOWER(drug), r'sitagliptin|saxagliptin|linagliptin') THEN 'DPP-4'
      WHEN REGEXP_CONTAINS(LOWER(drug), r'empagliflozin|dapagliflozin|canagliflozin') THEN 'SGLT2'
      WHEN REGEXP_CONTAINS(LOWER(drug), r'liraglutide|semaglutide|exenatide') THEN 'GLP-1'
      WHEN REGEXP_CONTAINS(LOWER(drug), r'pioglitazone|rosiglitazone') THEN 'TZDs'
      ELSE 'Other'
    END AS drug_class
  FROM
    physionet-data.mimiciv_3_1_hosp.prescriptions
  WHERE
    LOWER(drug) IS NOT NULL
),

first_prescriptions AS (
  SELECT
    subject_id,
    hadm_id,
    drug_class,
    starttime,
    ROW_NUMBER() OVER (PARTITION BY hadm_id, drug_class ORDER BY starttime) AS rn
  FROM
    drug_classifications
  WHERE
    drug_class != 'Other'
),

initiations AS (
  SELECT
    fp.subject_id,
    fp.hadm_id,
    fp.drug_class,
    fp.starttime,
    a.admittime,
    a.dischtime,
    CASE
      WHEN fp.starttime BETWEEN a.admittime AND a.admittime + INTERVAL 12 HOUR THEN 'First12h'
      WHEN fp.starttime BETWEEN a.dischtime - INTERVAL 48 HOUR AND a.dischtime THEN 'Final48h'
      ELSE 'Other'
    END AS time_window
  FROM
    first_prescriptions fp
  JOIN
    target_admissions a
    ON fp.hadm_id = a.hadm_id
  WHERE
    fp.rn = 1
),

eligible_patients AS (
  SELECT COUNT(DISTINCT hadm_id) AS total_patients
  FROM target_admissions
),

initiation_counts AS (
  SELECT
    drug_class,
    time_window,
    COUNT(DISTINCT hadm_id) AS initiated
  FROM
    initiations
  WHERE
    time_window IN ('First12h', 'Final48h')
  GROUP BY
    drug_class,
    time_window
)

SELECT
  ic.drug_class,
  ic.time_window,
  ROUND(100.0 * ic.initiated / ep.total_patients, 2) AS initiation_percentage
FROM
  initiation_counts ic
CROSS JOIN
  eligible_patients ep
ORDER BY
  ic.drug_class,
  ic.time_window;