WITH male_elderly AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 76 AND 86
),
cardiac_procs AS (
  SELECT
    p.subject_id,
    pr.hadm_id,
    COUNT(DISTINCT pr.icd_code) AS num_distinct_cardiac_procs
  FROM male_elderly p
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON p.subject_id = pr.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dpr
    ON pr.icd_code = dpr.icd_code
    AND pr.icd_version = dpr.icd_version
  WHERE LOWER(dpr.long_title) LIKE '%cardiac%'
  GROUP BY p.subject_id, pr.hadm_id
)
SELECT
  q[OFFSET(1)] AS q1,
  q[OFFSET(3)] AS q3,
  q[OFFSET(3)] - q[OFFSET(1)] AS iqr
FROM (
  SELECT APPROX_QUANTILES(num_distinct_cardiac_procs, 4) AS q
  FROM cardiac_procs
);