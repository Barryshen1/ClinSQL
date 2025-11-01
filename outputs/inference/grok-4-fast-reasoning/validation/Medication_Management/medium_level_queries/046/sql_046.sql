WITH cohort_hadm AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 63 AND 73
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '250.%') OR
      (d.icd_version = 10 AND d.icd_code LIKE 'E11%')
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
      WHERE d2.hadm_id = d.hadm_id
        AND (
          (d2.icd_version = 9 AND d2.icd_code LIKE '428%') OR
          (d2.icd_version = 10 AND d2.icd_code LIKE 'I50%')
        )
    )
),
clipped_periods AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admittime AS first_start,
    LEAST(TIMESTAMP_ADD(a.admittime, INTERVAL 1 DAY), a.dischtime) AS first_end,
    GREATEST(a.admittime, TIMESTAMP_SUB(a.dischtime, INTERVAL 1 DAY)) AS last_start,
    a.dischtime AS last_end
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN cohort_hadm ch ON a.hadm_id = ch.hadm_id
),
total_cohort AS (
  SELECT COUNT(*) AS n FROM clipped_periods
),
insulin_first AS (
  SELECT COUNT(DISTINCT p.hadm_id) * 100.0 / (SELECT n FROM total_cohort) AS pct
  FROM clipped_periods p
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    WHERE pr.hadm_id = p.hadm_id
      AND LOWER(pr.drug) LIKE '%insulin%'
      AND pr.starttime < p.first_end
      AND (pr.stoptime IS NULL OR pr.stoptime > p.first_start)
  )
),
oral_first AS (
  SELECT COUNT(DISTINCT p.hadm_id) * 100.0 / (SELECT n FROM total_cohort) AS pct
  FROM clipped_periods p
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    WHERE pr.hadm_id = p.hadm_id
      AND pr.route = 'PO'
      AND LOWER(pr.drug) NOT LIKE '%insulin%'
      AND (
        LOWER(pr.drug) LIKE '%metformin%' OR
        LOWER(pr.drug) LIKE '%glipizide%' OR
        LOWER(pr.drug) LIKE '%glyburide%' OR
        LOWER(pr.drug) LIKE '%glibenclamide%' OR
        LOWER(pr.drug) LIKE '%glimepiride%' OR
        LOWER(pr.drug) LIKE '%pioglitazone%' OR
        LOWER(pr.drug) LIKE '%rosiglitazone%' OR
        LOWER(pr.drug) LIKE '%sitagliptin%' OR
        LOWER(pr.drug) LIKE '%linagliptin%' OR
        LOWER(pr.drug) LIKE '%saxagliptin%' OR
        LOWER(pr.drug) LIKE '%alogliptin%' OR
        LOWER(pr.drug) LIKE '%canagliflozin%' OR
        LOWER(pr.drug) LIKE '%dapagliflozin%' OR
        LOWER(pr.drug) LIKE '%empagliflozin%' OR
        LOWER(pr.drug) LIKE '%ertugliflozin%' OR
        LOWER(pr.drug) LIKE '%repaglinide%' OR
        LOWER(pr.drug) LIKE '%nateglinide%' OR
        LOWER(pr.drug) LIKE '%acarbose%' OR
        LOWER(pr.drug) LIKE '%miglitol%'
      )
      AND pr.starttime < p.first_end
      AND (pr.stoptime IS NULL OR pr.stoptime > p.first_start)
  )
),
insulin_last AS (
  SELECT COUNT(DISTINCT p.hadm_id) * 100.0 / (SELECT n FROM total_cohort) AS pct
  FROM clipped_periods p
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    WHERE pr.hadm_id = p.hadm_id
      AND LOWER(pr.drug) LIKE '%insulin%'
      AND pr.starttime < p.last_end
      AND (pr.stoptime IS NULL OR pr.stoptime > p.last_start)
  )
),
oral_last AS (
  SELECT COUNT(DISTINCT p.hadm_id) * 100.0 / (SELECT n FROM total_cohort) AS pct
  FROM clipped_periods p
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    WHERE pr.hadm_id = p.hadm_id
      AND pr.route = 'PO'
      AND LOWER(pr.drug) NOT LIKE '%insulin%'
      AND (
        LOWER(pr.drug) LIKE '%metformin%' OR
        LOWER(pr.drug) LIKE '%glipizide%' OR
        LOWER(pr.drug) LIKE '%glyburide%' OR
        LOWER(pr.drug) LIKE '%glibenclamide%' OR
        LOWER(pr.drug) LIKE '%glimepiride%' OR
        LOWER(pr.drug) LIKE '%pioglitazone%' OR
        LOWER(pr.drug) LIKE '%rosiglitazone%' OR
        LOWER(pr.drug) LIKE '%sitagliptin%' OR
        LOWER(pr.drug) LIKE '%linagliptin%' OR
        LOWER(pr.drug) LIKE '%saxagliptin%' OR
        LOWER(pr.drug) LIKE '%alogliptin%' OR
        LOWER(pr.drug) LIKE '%canagliflozin%' OR
        LOWER(pr.drug) LIKE '%dapagliflozin%' OR
        LOWER(pr.drug) LIKE '%empagliflozin%' OR
        LOWER(pr.drug) LIKE '%ertugliflozin%' OR
        LOWER(pr.drug) LIKE '%repaglinide%' OR
        LOWER(pr.drug) LIKE '%nateglinide%' OR
        LOWER(pr.drug) LIKE '%acarbose%' OR
        LOWER(pr.drug) LIKE '%miglitol%'
      )
      AND pr.starttime < p.last_end
      AND (pr.stoptime IS NULL OR pr.stoptime > p.last_start)
  )
)
SELECT
  (SELECT pct FROM insulin_first) AS insulin_first_pct,
  (SELECT pct FROM oral_first) AS oral_first_pct,
  (SELECT pct FROM insulin_last) AS insulin_last_pct,
  (SELECT pct FROM oral_last) AS oral_last_pct,
  (SELECT pct FROM insulin_last) - (SELECT pct FROM insulin_first) AS insulin_net_pp,
  (SELECT pct FROM oral_last) - (SELECT pct FROM oral_first) AS oral_net_pp;