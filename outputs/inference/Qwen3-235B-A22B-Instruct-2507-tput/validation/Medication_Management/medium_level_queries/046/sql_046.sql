WITH patient_admissions AS (
  SELECT
    p.subject_id,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 63 AND 73
),

diagnoses AS (
  SELECT
    di.hadm_id,
    MAX(CASE WHEN SUBSTR(dicd.icd_code, 1, 3) = 'E11' AND dicd.icd_version = 10 THEN 1 ELSE 0 END) AS has_t2dm,
    MAX(CASE WHEN SUBSTR(dicd.icd_code, 1, 3) = 'I50' AND dicd.icd_version = 10 THEN 1 ELSE 0 END) AS has_hf
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses dicd
    ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
  GROUP BY di.hadm_id
),

qualified_admissions AS (
  SELECT pa.*
  FROM patient_admissions pa
  INNER JOIN diagnoses d
    ON pa.hadm_id = d.hadm_id
  WHERE d.has_t2dm = 1 AND d.has_hf = 1
),

medications AS (
  SELECT
    qa.hadm_id,
    LOWER(pres.drug) AS drug_name,
    pres.starttime,
    pres.stoptime,
    CASE
      WHEN LOWER(pres.drug) LIKE '%insulin%' THEN 'insulin'
      WHEN LOWER(pres.drug) NOT LIKE '%insulin%'
        AND LOWER(pres.drug) IN (
          'metformin', 'glipizide', 'glyburide', 'glimepiride', 'sitagliptin', 'saxagliptin',
          'linagliptin', 'alogliptin', 'pioglitazone', 'rosiglitazone', 'repaglinide', 'nateglinide',
          'canagliflozin', 'dapagliflozin', 'empagliflozin', 'ertugliflozin', 'acarbose', 'miglitol'
        )
        OR LOWER(pres.drug) LIKE '%metformin%'
        OR LOWER(pres.drug) LIKE '%gliptin%'
        OR LOWER(pres.drug) LIKE '%gliflozin%'
        OR LOWER(pres.drug) LIKE '%glitazone%'
        OR LOWER(pres.drug) LIKE '%repaglinide%'
        OR LOWER(pres.drug) LIKE '%acarbose%'
        THEN 'oral_agent'
      ELSE NULL
    END AS drug_class
  FROM qualified_admissions qa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.prescriptions pres
    ON qa.hadm_id = pres.hadm_id
  WHERE pres.drug_type = 'MAIN'  -- Focus on primary medications
),

use_in_windows AS (
  SELECT
    m.hadm_id,
    m.drug_class,
    MAX(CASE
      WHEN m.starttime IS NOT NULL
       AND m.starttime >= qa.admittime
       AND m.starttime <= qa.admittime + INTERVAL '24' HOUR
      THEN 1 ELSE 0 END) AS used_in_first_24h,
    MAX(CASE
      WHEN m.starttime < qa.dischtime
       AND COALESCE(m.stoptime, qa.dischtime) > qa.dischtime - INTERVAL '24' HOUR
      THEN 1 ELSE 0 END) AS used_in_final_24h
  FROM medications m
  INNER JOIN qualified_admissions qa
    ON m.hadm_id = qa.hadm_id
  WHERE m.drug_class IN ('insulin', 'oral_agent')
  GROUP BY m.hadm_id, m.drug_class
),

summary AS (
  SELECT
    drug_class,
    AVG(used_in_first_24h) * 100 AS first_24h_prevalence,
    AVG(used_in_final_24h) * 100 AS final_24h_prevalence,
    (AVG(used_in_final_24h) - AVG(used_in_first_24h)) * 100 AS net_change_pp
  FROM use_in_windows
  GROUP BY drug_class
)

SELECT
  drug_class,
  ROUND(first_24h_prevalence, 2) AS first_24h_prevalence_pct,
  ROUND(final_24h_prevalence, 2) AS final_24h_prevalence_pct,
  ROUND(net_change_pp, 2) AS net_change_pp
FROM summary
ORDER BY drug_class;