WITH base_cohort AS (
  SELECT DISTINCT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    p.dod,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  WHERE p.gender = 'F'
    AND (
      (di.icd_version = 9 AND di.icd_code LIKE '453.4%') OR
      (di.icd_version = 10 AND di.icd_code LIKE 'I82%')
    )
    AND a.admittime IS NOT NULL
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 59 AND 69
),
comorb_score AS (
  SELECT
    bc.*,
    COUNT(DISTINCT di.icd_code) AS score
  FROM base_cohort bc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON bc.hadm_id = di.hadm_id
  GROUP BY
    bc.hadm_id,
    bc.subject_id,
    bc.admittime,
    bc.dod,
    bc.anchor_age
),
with_percentile AS (
  SELECT
    *,
    PERCENTILE_CONT(score, 0.75) OVER() AS p75
  FROM comorb_score
),
high_comorb AS (
  SELECT *
  FROM with_percentile
  WHERE score > p75
),
pe_cohort AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (
      (icd_version = 9 AND icd_code LIKE '415.1%') OR
      (icd_version = 10 AND icd_code LIKE 'I26%')
    )
)
SELECT
  COUNT(*) AS cohort_size,
  SAFE_DIVIDE(
    SUM(CASE WHEN dod IS NOT NULL AND dod <= DATE_ADD(DATE(admittime), INTERVAL 30 DAY) THEN 1 ELSE 0 END),
    COUNT(*)
  ) AS `30-day_mortality_rate`,
  SAFE_DIVIDE(
    SUM(CASE WHEN hc.hadm_id IN (SELECT hadm_id FROM pe_cohort) THEN 1 ELSE 0 END),
    COUNT(*)
  ) AS `major_complication_rate`,
  (SELECT APPROX_QUANTILES(DATE_DIFF(dod, DATE(admittime), DAY), 3)[OFFSET(1)]
   FROM high_comorb
   WHERE dod IS NOT NULL
  ) AS median_survival_days,
  (SELECT APPROX_QUANTILES(score, 5)[OFFSET(1)] FROM high_comorb) AS score_q1,
  (SELECT APPROX_QUANTILES(score, 5)[OFFSET(2)] FROM high_comorb) AS score_q2,
  (SELECT APPROX_QUANTILES(score, 5)[OFFSET(3)] FROM high_comorb) AS score_q3
FROM high_comorb hc;