WITH cohort AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  -- age and gender filter
  WHERE pat.anchor_age BETWEEN 77 AND 87
    AND pat.gender = 'M'
),
dx AS (
  SELECT d.subject_id, d.hadm_id,
    MAX(CASE WHEN ( (d.icd_version = 10 AND icd.icd_code LIKE 'E1%' ) 
                 OR (d.icd_version = 9 AND icd.icd_code LIKE '250%') )
             THEN 1 ELSE 0 END) AS has_diabetes,
    MAX(CASE WHEN ( (d.icd_version = 10 AND icd.icd_code LIKE 'I50%' )
                 OR (d.icd_version = 9 AND icd.icd_code LIKE '428%') )
             THEN 1 ELSE 0 END) AS has_hf
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS icd
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  GROUP BY d.subject_id, d.hadm_id
),
final_cohort AS (
  SELECT c.*
  FROM cohort c
  JOIN dx
    ON c.subject_id = dx.subject_id AND c.hadm_id = dx.hadm_id
  WHERE dx.has_diabetes = 1
    AND dx.has_hf = 1
),
med_flags AS (
  SELECT fc.subject_id, fc.hadm_id,
    MAX(CASE WHEN LOWER(pr.drug) LIKE '%insulin%' 
             AND pr.starttime BETWEEN fc.admittime AND DATETIME_ADD(fc.admittime, INTERVAL 48 HOUR)
             THEN 1 ELSE 0 END) AS insulin_early,
    MAX(CASE WHEN LOWER(pr.drug) LIKE '%insulin%' 
             AND pr.starttime BETWEEN DATETIME_SUB(fc.dischtime, INTERVAL 72 HOUR) AND fc.dischtime
             THEN 1 ELSE 0 END) AS insulin_late,
    MAX(CASE WHEN (
                   LOWER(pr.drug) LIKE '%metformin%' OR
                   LOWER(pr.drug) LIKE '%glipizide%' OR
                   LOWER(pr.drug) LIKE '%glyburide%' OR
                   LOWER(pr.drug) LIKE '%glimepiride%' OR
                   LOWER(pr.drug) LIKE '%pioglitazone%' OR
                   LOWER(pr.drug) LIKE '%rosiglitazone%' OR
                   LOWER(pr.drug) LIKE '%sitagliptin%' OR
                   LOWER(pr.drug) LIKE '%linagliptin%' OR
                   LOWER(pr.drug) LIKE '%alogliptin%' OR
                   LOWER(pr.drug) LIKE '%canagliflozin%' OR
                   LOWER(pr.drug) LIKE '%dapagliflozin%' OR
                   LOWER(pr.drug) LIKE '%empagliflozin%'
                 )
             AND LOWER(pr.drug) NOT LIKE '%insulin%'
             AND pr.starttime BETWEEN fc.admittime AND DATETIME_ADD(fc.admittime, INTERVAL 48 HOUR)
             THEN 1 ELSE 0 END) AS oral_early,
    MAX(CASE WHEN (
                   LOWER(pr.drug) LIKE '%metformin%' OR
                   LOWER(pr.drug) LIKE '%glipizide%' OR
                   LOWER(pr.drug) LIKE '%glyburide%' OR
                   LOWER(pr.drug) LIKE '%glimepiride%' OR
                   LOWER(pr.drug) LIKE '%pioglitazone%' OR
                   LOWER(pr.drug) LIKE '%rosiglitazone%' OR
                   LOWER(pr.drug) LIKE '%sitagliptin%' OR
                   LOWER(pr.drug) LIKE '%linagliptin%' OR
                   LOWER(pr.drug) LIKE '%alogliptin%' OR
                   LOWER(pr.drug) LIKE '%canagliflozin%' OR
                   LOWER(pr.drug) LIKE '%dapagliflozin%' OR
                   LOWER(pr.drug) LIKE '%empagliflozin%'
                 )
             AND LOWER(pr.drug) NOT LIKE '%insulin%'
             AND pr.starttime BETWEEN DATETIME_SUB(fc.dischtime, INTERVAL 72 HOUR) AND fc.dischtime
             THEN 1 ELSE 0 END) AS oral_late
  FROM final_cohort fc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    ON fc.subject_id = pr.subject_id AND fc.hadm_id = pr.hadm_id
  GROUP BY fc.subject_id, fc.hadm_id
),
rates AS (
  SELECT
    COUNT(*) AS total_admissions,
    SUM(insulin_early) AS ins_e,
    SUM(insulin_late) AS ins_l,
    SUM(oral_early) AS oral_e,
    SUM(oral_late) AS oral_l
  FROM med_flags
)
SELECT
  'Insulin' AS med_class,
  ROUND(100.0 * ins_e / total_admissions, 2) AS early_rate_percent,
  ROUND(100.0 * ins_l / total_admissions, 2) AS late_rate_percent,
  ROUND(100.0 * (ins_l - ins_e) / total_admissions, 2) AS net_change_pp
FROM rates
UNION ALL
SELECT
  'Oral agents' AS med_class,
  ROUND(100.0 * oral_e / total_admissions, 2) AS early_rate_percent,
  ROUND(100.0 * oral_l / total_admissions, 2) AS late_rate_percent,
  ROUND(100.0 * (oral_l - oral_e) / total_admissions, 2) AS net_change_pp
FROM rates;