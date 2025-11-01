WITH qualifying_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' 
    AND anchor_age BETWEEN 63 AND 73
),
all_hadms AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN qualifying_patients qp ON a.subject_id = qp.subject_id
),
cardiac_procedures AS (
  SELECT p.subject_id, p.hadm_id, p.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  INNER JOIN qualifying_patients qp ON p.subject_id = qp.subject_id
  WHERE (
    (p.icd_version = 9 AND (p.icd_code LIKE '35%' OR p.icd_code LIKE '36%' OR 
                               p.icd_code LIKE '37%' OR p.icd_code LIKE '38%' OR 
                               p.icd_code LIKE '39%'))
    OR 
    (p.icd_version = 10 AND p.icd_code LIKE '02%')
  )
),
counts_per_hadm AS (
  SELECT 
    ah.hadm_id,
    COALESCE(cp.num_distinct, 0) AS num_distinct_cardiac
  FROM all_hadms ah
  LEFT JOIN (
    SELECT hadm_id, COUNT(DISTINCT icd_code) AS num_distinct
    FROM cardiac_procedures
    GROUP BY hadm_id
  ) cp ON ah.hadm_id = cp.hadm_id
)
SELECT APPROX_QUANTILES(num_distinct_cardiac, 4)[OFFSET(3)] AS p75th_percentile
FROM counts_per_hadm;