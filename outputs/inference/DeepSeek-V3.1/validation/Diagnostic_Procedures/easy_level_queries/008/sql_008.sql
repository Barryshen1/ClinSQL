WITH patient_cohort AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 88 AND 98
),

echo_procedures AS (
  SELECT picd.subject_id, picd.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` picd
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dicd
    ON picd.icd_code = dicd.icd_code AND picd.icd_version = dicd.icd_version
  WHERE LOWER(dicd.long_title) LIKE '%echocardiogram%'
),

patient_echo_count AS (
  SELECT 
    pc.subject_id,
    COUNT(DISTINCT ep.icd_code) AS distinct_echo_count
  FROM patient_cohort pc
  LEFT JOIN echo_procedures ep
    ON pc.subject_id = ep.subject_id
  GROUP BY pc.subject_id
)

SELECT 
  APPROX_QUANTILES(distinct_echo_count, 100)[OFFSET(25)] AS percentile_25
FROM patient_echo_count;