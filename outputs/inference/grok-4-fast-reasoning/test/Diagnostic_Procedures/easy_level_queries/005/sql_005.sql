WITH patient_cohort AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' 
    AND anchor_age BETWEEN 57 AND 67
),
echo_procs AS (
  SELECT DISTINCT p.subject_id, p.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d 
    ON p.icd_code = d.icd_code 
    AND p.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%echocardiography%' 
     OR LOWER(d.long_title) LIKE '%echo%'
),
echo_counts AS (
  SELECT pc.subject_id, 
         COUNT(DISTINCT ep.icd_code) AS num_distinct_echo
  FROM patient_cohort pc
  LEFT JOIN echo_procs ep 
    ON pc.subject_id = ep.subject_id
  GROUP BY pc.subject_id
)
SELECT APPROX_QUANTILES(num_distinct_echo, 4)[OFFSET(3)] AS p75th_percentile
FROM echo_counts;