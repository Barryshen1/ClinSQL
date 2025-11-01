WITH cohort AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 57 AND 67
),
echo_counts AS (
  SELECT
    c.subject_id,
    COUNT(DISTINCT p_icd.icd_code) AS distinct_echo_procs
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON c.subject_id = adm.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p_icd
    ON adm.subject_id = p_icd.subject_id
    AND adm.hadm_id = p_icd.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d_icd
    ON p_icd.icd_code = d_icd.icd_code
    AND p_icd.icd_version = d_icd.icd_version
  WHERE LOWER(d_icd.long_title) LIKE '%echocardiography%'
     OR d_icd.icd_code IS NULL -- allow patients with no echo procedures
  GROUP BY c.subject_id
)
SELECT
  PERCENTILE_CONT(distinct_echo_procs, 0.75) OVER() AS pct75_distinct_echo_per_patient
FROM echo_counts
LIMIT 1;