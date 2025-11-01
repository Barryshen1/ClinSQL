WITH echo_per_patient AS (
  SELECT
    p.subject_id,
    COUNT(DISTINCT pr.icd_code) AS num_distinct_echo
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON p.subject_id = pr.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dpr
    ON pr.icd_code = dpr.icd_code
    AND pr.icd_version = dpr.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 88 AND 98
    AND UPPER(dpr.long_title) LIKE '%ECHOCARDIO%'
  GROUP BY
    p.subject_id
)
SELECT
  PERCENTILE_CONT(num_distinct_echo, 0.25) OVER() AS pct25_distinct_echo_per_patient
FROM
  echo_per_patient
LIMIT 1;