WITH target_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 75 AND 85
),
procedure_events AS (
  SELECT p.subject_id,
         pi.icd_code,
         pi.icd_version
  FROM target_patients p
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    ON p.subject_id = pi.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON pi.icd_code = dp.icd_code
   AND pi.icd_version = dp.icd_version
  WHERE LOWER(dp.long_title) LIKE '%catheter ablation%'
     OR LOWER(dp.long_title) LIKE '%cardioversion%'
),
counts_per_patient AS (
  SELECT subject_id,
         COUNT(DISTINCT CONCAT(icd_code, '-', icd_version)) AS distinct_proc_count
  FROM procedure_events
  GROUP BY subject_id
),
iqr_calc AS (
  SELECT
    qs[OFFSET(1)] AS q25,
    qs[OFFSET(3)] AS q75
  FROM (
    SELECT APPROX_QUANTILES(distinct_proc_count, 4) AS qs
    FROM counts_per_patient
  )
)
SELECT q75 - q25 AS iqr_distinct_procedures
FROM iqr_calc;