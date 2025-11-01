WITH cohort AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 52 AND 62
),
admissions_cohort AS (
  SELECT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN cohort c ON a.subject_id = c.subject_id
),
valve_procedures AS (
  SELECT p.subject_id, p.hadm_id, p.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%valve%'
    AND (LOWER(d.long_title) LIKE '%repair%' OR LOWER(d.long_title) LIKE '%replace%' OR LOWER(d.long_title) LIKE '%replacement%')
),
valve_counts AS (
  SELECT ac.hadm_id,
         COUNT(DISTINCT vp.icd_code) AS num_valve_procedures
  FROM admissions_cohort ac
  LEFT JOIN valve_procedures vp
    ON ac.subject_id = vp.subject_id AND ac.hadm_id = vp.hadm_id
  GROUP BY ac.hadm_id
)
SELECT
  APPROX_QUANTILES(num_valve_procedures, 4)[OFFSET(1)] AS percentile_25,
  APPROX_QUANTILES(num_valve_procedures, 4)[OFFSET(3)] AS percentile_75
FROM valve_counts
;