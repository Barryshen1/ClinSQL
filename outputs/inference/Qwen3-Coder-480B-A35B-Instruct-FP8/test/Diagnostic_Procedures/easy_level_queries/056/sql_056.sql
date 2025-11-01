WITH target_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 43 AND 53
),
mech_support_procs AS (
  SELECT p.subject_id,
         COUNT(DISTINCT CONCAT(p.icd_code, '-', p.icd_version)) AS distinct_procedure_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code
    AND p.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%mechanical%' AND LOWER(d.long_title) LIKE '%support%'
  GROUP BY p.subject_id
)
SELECT
  APPROX_QUANTILES(COALESCE(m.distinct_procedure_count, 0), 4)[OFFSET(1)] AS percentile_25th
FROM target_patients t
LEFT JOIN mech_support_procs m
  ON t.subject_id = m.subject_id;