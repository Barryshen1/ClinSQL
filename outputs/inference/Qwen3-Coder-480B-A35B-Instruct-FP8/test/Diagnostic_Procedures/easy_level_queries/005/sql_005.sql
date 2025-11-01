WITH eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 57 AND 67
),
echo_procedures AS (
  SELECT p.subject_id,
         COUNT(DISTINCT p.icd_code) AS distinct_echo_count
  FROM eligible_patients ep
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    ON ep.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code
    AND p.icd_version = d.icd_version
  WHERE REGEXP_CONTAINS(UPPER(d.long_title), r'ECHOCARDIOGRAPHY')
  GROUP BY p.subject_id
),
all_counts AS (
  SELECT ep.subject_id,
         COALESCE(e.distinct_echo_count, 0) AS distinct_echo_count
  FROM eligible_patients ep
  LEFT JOIN echo_procedures e
    ON ep.subject_id = e.subject_id
)
SELECT APPROX_QUANTILES(distinct_echo_count, 100)[OFFSET(75)] AS percentile_75
FROM all_counts;