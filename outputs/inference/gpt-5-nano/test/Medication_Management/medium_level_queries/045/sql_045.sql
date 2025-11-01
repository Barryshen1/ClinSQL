WITH eligible AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 54 AND 64
  GROUP BY a.subject_id, a.hadm_id, a.admittime, a.dischtime
  HAVING
    SUM(CASE WHEN di.icd_code LIKE '250%' THEN 1 ELSE 0 END) > 0 -- diabetes
    AND SUM(CASE WHEN di.icd_code LIKE '428%' THEN 1 ELSE 0 END) > 0 -- heart failure
),

flags AS (
  SELECT
    e.subject_id,
    e.hadm_id,
    e.admittime,
    e.dischtime,
    MAX(CASE
          WHEN (LOWER(pr.drug_type) LIKE '%insulin%' OR LOWER(pr.drug) LIKE '%insulin%')
               AND pr.starttime BETWEEN e.admittime AND TIMESTAMP_ADD(e.admittime, INTERVAL 12 HOUR)
          THEN 1 ELSE 0 END) AS insulin_12h,
    MAX(CASE
          WHEN (
                LOWER(pr.drug_type) LIKE '%oral%' OR
                LOWER(pr.drug) LIKE '%metformin%' OR
                LOWER(pr.drug) LIKE '%glyburide%' OR
                LOWER(pr.drug) LIKE '%glipizide%' OR
                LOWER(pr.drug) LIKE '%glimepiride%' OR
                LOWER(pr.drug) LIKE '%pioglitazone%' OR
                LOWER(pr.drug) LIKE '%rosiglitazone%' OR
                LOWER(pr.drug) LIKE '%acarbose%' OR
                LOWER(pr.drug) LIKE '%miglitol%' OR
                LOWER(pr.drug) LIKE '%sitagliptin%' OR
                LOWER(pr.drug) LIKE '%linagliptin%' OR
                LOWER(pr.drug) LIKE '%dulaglutide%' OR
                LOWER(pr.drug) LIKE '%exenatide%' OR
                LOWER(pr.drug) LIKE '%liraglutide%' OR
                LOWER(pr.drug) LIKE '%dapagliflozin%' OR
                LOWER(pr.drug) LIKE '%canagliflozin%' OR
                LOWER(pr.drug) LIKE '%empagliflozin%' OR
                LOWER(pr.drug) LIKE '%ertugliflozin%' OR
                LOWER(pr.drug) LIKE '%gliflozin%'
              )
               AND pr.starttime BETWEEN e.admittime AND TIMESTAMP_ADD(e.admittime, INTERVAL 12 HOUR)
          THEN 1 ELSE 0 END) AS oral_12h,
    MAX(CASE
          WHEN (LOWER(pr.drug_type) LIKE '%insulin%' OR LOWER(pr.drug) LIKE '%insulin%')
               AND pr.starttime BETWEEN TIMESTAMP_SUB(e.dischtime, INTERVAL 48 HOUR) AND e.dischtime
          THEN 1 ELSE 0 END) AS insulin_48h,
    MAX(CASE
          WHEN (
                LOWER(pr.drug_type) LIKE '%oral%' OR
                LOWER(pr.drug) LIKE '%metformin%' OR
                LOWER(pr.drug) LIKE '%glyburide%' OR
                LOWER(pr.drug) LIKE '%glipizide%' OR
                LOWER(pr.drug) LIKE '%glimepiride%' OR
                LOWER(pr.drug) LIKE '%pioglitazone%' OR
                LOWER(pr.drug) LIKE '%rosiglitazone%' OR
                LOWER(pr.drug_type) LIKE '%acarbose%' OR
                LOWER(pr.drug) LIKE '%miglitol%' OR
                LOWER(pr.drug) LIKE '%sitagliptin%' OR
                LOWER(pr.drug) LIKE '%linagliptin%' OR
                LOWER(pr.drug) LIKE '%dulaglutide%' OR
                LOWER(pr.drug) LIKE '%exenatide%' OR
                LOWER(pr.drug) LIKE '%liraglutide%' OR
                LOWER(pr.drug) LIKE '%dapagliflozin%' OR
                LOWER(pr.drug) LIKE '%canagliflozin%' OR
                LOWER(pr.drug) LIKE '%empagliflozin%' OR
                LOWER(pr.drug) LIKE '%ertugliflozin%' OR
                LOWER(pr.drug) LIKE '%gliflozin%'
              )
               AND pr.starttime BETWEEN TIMESTAMP_SUB(e.dischtime, INTERVAL 48 HOUR) AND e.dischtime
          THEN 1 ELSE 0 END) AS oral_48h
  FROM eligible e
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    ON pr.subject_id = e.subject_id AND pr.hadm_id = e.hadm_id
  GROUP BY e.subject_id, e.hadm_id, e.admittime, e.dischtime
)

SELECT
  COUNT(*) AS n_patients,
  SUM(insulin_12h) AS n_insulin_12h,
  SUM(oral_12h) AS n_oral_12h,
  SUM(insulin_48h) AS n_insulin_48h,
  SUM(oral_48h) AS n_oral_48h,
  SAFE_DIVIDE(SUM(insulin_12h), COUNT(*)) AS insulin_prev_12h,
  SAFE_DIVIDE(SUM(oral_12h), COUNT(*)) AS oral_prev_12h,
  SAFE_DIVIDE(SUM(insulin_48h), COUNT(*)) AS insulin_prev_48h,
  SAFE_DIVIDE(SUM(oral_48h), COUNT(*)) AS oral_prev_48h,
  (SAFE_DIVIDE(SUM(insulin_12h), COUNT(*)) - SAFE_DIVIDE(SUM(oral_12h), COUNT(*))) AS delta_12h,
  (SAFE_DIVIDE(SUM(insulin_48h), COUNT(*)) - SAFE_DIVIDE(SUM(oral_48h), COUNT(*))) AS delta_48h,
  ((SAFE_DIVIDE(SUM(insulin_12h), COUNT(*)) - SAFE_DIVIDE(SUM(oral_12h), COUNT(*)))
   - (SAFE_DIVIDE(SUM(insulin_48h), COUNT(*)) - SAFE_DIVIDE(SUM(oral_48h), COUNT(*)))) AS net_change_pp
FROM flags;