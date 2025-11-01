WITH diabetes_hadm AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.hadm_id = di.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
    AND (
          (di.icd_version = 9 AND di.icd_code LIKE '250%')
          OR (di.icd_version = 10 AND di.icd_code LIKE 'E1%')
        )
),
heartfailure_hadm AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.hadm_id = di.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
    AND (
          (di.icd_version = 9 AND di.icd_code LIKE '428%')
          OR (di.icd_version = 10 AND di.icd_code LIKE 'I50%')
        )
),
eligible_hadm AS (
  SELECT d.hadm_id
  FROM diabetes_hadm AS d
  INNER JOIN heartfailure_hadm AS h
    ON d.hadm_id = h.hadm_id
),
admit_times AS (
  SELECT a.hadm_id, a.subject_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  WHERE a.hadm_id IN (SELECT hadm_id FROM eligible_hadm)
),
flags AS (
  SELECT
    at.hadm_id,
    MAX(CASE
          WHEN LOWER(pr.drug) LIKE '%insulin%'
               AND pr.starttime BETWEEN at.admittime AND TIMESTAMP_ADD(at.admittime, INTERVAL 48 HOUR)
          THEN 1 ELSE 0 END) AS insulin_0_48,
    MAX(CASE
          WHEN LOWER(pr.drug) LIKE '%insulin%'
               AND pr.starttime BETWEEN TIMESTAMP_SUB(at.dischtime, INTERVAL 72 HOUR) AND at.dischtime
          THEN 1 ELSE 0 END) AS insulin_final72,
    MAX(CASE
          WHEN (
                 LOWER(pr.drug) LIKE '%metformin%' OR
                 LOWER(pr.drug) LIKE '%glyburide%' OR
                 LOWER(pr.drug) LIKE '%glipizide%' OR
                 LOWER(pr.drug) LIKE '%glimepiride%' OR
                 LOWER(pr.drug) LIKE '%pioglitazone%' OR
                 LOWER(pr.drug) LIKE '%rosiglitazone%' OR
                 LOWER(pr.drug) LIKE '%acarbose%' OR
                 LOWER(pr.drug) LIKE '%nateglinide%' OR
                 LOWER(pr.drug) LIKE '%repaglinide%' OR
                 LOWER(pr.drug) LIKE '%linagliptin%' OR
                 LOWER(pr.drug) LIKE '%sitagliptin%'
               )
               AND pr.starttime BETWEEN at.admittime AND TIMESTAMP_ADD(at.admittime, INTERVAL 48 HOUR)
          THEN 1 ELSE 0 END) AS oral_0_48,
    MAX(CASE
          WHEN (
                 LOWER(pr.drug) LIKE '%metformin%' OR
                 LOWER(pr.drug) LIKE '%glyburide%' OR
                 LOWER(pr.drug) LIKE '%glipizide%' OR
                 LOWER(pr.drug) LIKE '%glimepiride%' OR
                 LOWER(pr.drug) LIKE '%pioglitazone%' OR
                 LOWER(pr.drug) LIKE '%rosiglitazone%' OR
                 LOWER(pr.drug) LIKE '%acarbose%' OR
                 LOWER(pr.drug) LIKE '%nateglinide%' OR
                 LOWER(pr.drug) LIKE '%repaglinide%' OR
                 LOWER(pr.drug) LIKE '%linagliptin%' OR
                 LOWER(pr.drug) LIKE '%sitagliptin%'
               )
               AND pr.starttime BETWEEN TIMESTAMP_SUB(at.dischtime, INTERVAL 72 HOUR) AND at.dischtime
          THEN 1 ELSE 0 END) AS oral_final72
  FROM admit_times AS at
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    ON pr.hadm_id = at.hadm_id
  GROUP BY at.hadm_id
)
SELECT
  COUNT(*) AS total_admissions,
  AVG(CAST(insulin_0_48 AS FLOAT64)) * 100 AS insulin_0_48_rate_pp,
  AVG(CAST(oral_0_48 AS FLOAT64)) * 100 AS oral_0_48_rate_pp,
  AVG(CAST(insulin_final72 AS FLOAT64)) * 100 AS insulin_final72_rate_pp,
  AVG(CAST(oral_final72 AS FLOAT64)) * 100 AS oral_final72_rate_pp,
  (AVG(CAST(insulin_0_48 AS FLOAT64)) * 100 - AVG(CAST(oral_0_48 AS FLOAT64)) * 100) AS diff_0_48_pp,
  (AVG(CAST(insulin_final72 AS FLOAT64)) * 100 - AVG(CAST(oral_final72 AS FLOAT64)) * 100) AS diff_final72_pp
FROM flags;