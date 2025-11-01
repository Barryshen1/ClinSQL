WITH qualifying_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 78 AND 88
),
relevant_procedures AS (
  SELECT p.subject_id, p.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code
    AND p.icd_version = d.icd_version
  WHERE d.long_title LIKE '%pacemaker%'
     OR d.long_title LIKE '%defibrillator%'
),
patient_counts AS (
  SELECT 
    qp.subject_id,
    COUNT(DISTINCT rp.icd_code) AS num_distinct_procedures
  FROM qualifying_patients qp
  LEFT JOIN relevant_procedures rp
    ON qp.subject_id = rp.subject_id
  GROUP BY qp.subject_id
)
SELECT 
  APPROX_QUANTILES(num_distinct_procedures, 4)[OFFSET(1)] AS p25
FROM patient_counts;