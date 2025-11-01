WITH cohort AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 36 AND 46
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '250%')
          OR (d.icd_version = 10 AND d.icd_code BETWEEN 'E08' AND 'E13')
        )
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '428%')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
        )
    )
),
prescriptions AS (
  SELECT
    p.hadm_id,
    CASE
      WHEN p.starttime BETWEEN c.admittime AND c.admittime + INTERVAL 48 HOUR THEN 1
      ELSE 0
    END AS in_first_48h,
    CASE
      WHEN p.starttime BETWEEN c.dischtime - INTERVAL 12 HOUR AND c.dischtime THEN 1
      ELSE 0
    END AS in_last_12h,
    CASE
      WHEN LOWER(p.drug) LIKE '%metformin%' THEN 'biguanide'
      WHEN LOWER(p.drug) LIKE '%glipizide%' THEN 'sulfonylurea'
      WHEN LOWER(p.drug) LIKE '%sitagliptin%' THEN 'dpp4'
      WHEN LOWER(p.drug) LIKE '%empagliflozin%' THEN 'sglt2'
      WHEN LOWER(p.drug) LIKE '%insulin%' THEN 'insulin'
      WHEN LOWER(p.drug) LIKE '%glimepiride%' THEN 'sulfonylurea'
      WHEN LOWER(p.drug) LIKE '%pioglitazone%' THEN 'thiazolidinedione'
      WHEN LOWER(p.drug) LIKE '%exenatide%' THEN 'glp1'
      WHEN LOWER(p.drug) LIKE '%metoprolol%' THEN 'beta_blocker'
      WHEN LOWER(p.drug) LIKE '%atenolol%' THEN 'beta_blocker'
      WHEN LOWER(p.drug) LIKE '%lisinopril%' THEN 'ace_inhibitor'
      WHEN LOWER(p.drug) LIKE '%enalapril%' THEN 'ace_inhibitor'
      WHEN LOWER(p.drug) LIKE '%losartan%' THEN 'arb'
      WHEN LOWER(p.drug) LIKE '%valsartan%' THEN 'arb'
      WHEN LOWER(p.drug) LIKE '%furosemide%' THEN 'loop_diuretic'
      WHEN LOWER(p.drug) LIKE '%hydrochlorothiazide%' THEN 'thiazide_diuretic'
      WHEN LOWER(p.drug) LIKE '%atorvastatin%' THEN 'statin'
      WHEN LOWER(p.drug) LIKE '%simvastatin%' THEN 'statin'
      WHEN LOWER(p.drug) LIKE '%amlodipine%' THEN 'calcium_channel_blocker'
      WHEN LOWER(p.drug) LIKE '%digoxin%' THEN 'cardiac_glycoside'
      ELSE NULL
    END AS drug_class
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN
    cohort c
    ON p.hadm_id = c.hadm_id
)
SELECT
  drug_class,
  COUNT(DISTINCT CASE WHEN in_first_48h = 1 THEN hadm_id END) * 100.0 / (SELECT COUNT(*) FROM cohort) AS first_48h_prevalence,
  COUNT(DISTINCT CASE WHEN in_last_12h = 1 THEN hadm_id END) * 100.0 / (SELECT COUNT(*) FROM cohort) AS last_12h_prevalence,
  (COUNT(DISTINCT CASE WHEN in_first_48h = 1 THEN hadm_id END) - COUNT(DISTINCT CASE WHEN in_last_12h = 1 THEN hadm_id END)) * 100.0 / (SELECT COUNT(*) FROM cohort) AS absolute_difference
FROM
  prescriptions
WHERE
  drug_class IS NOT NULL
GROUP BY
  drug_class
ORDER BY
  drug_class;