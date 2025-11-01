WITH cohort AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    LOWER(pr.drug) AS drug_lower,
    pr.starttime,
    pr.stoptime,
    DATE_DIFF(DATE(pr.stoptime), DATE(pr.starttime), DAY) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pa
    ON pr.subject_id = pa.subject_id
  WHERE
    pa.gender = 'F'
    AND pa.anchor_age BETWEEN 90 AND 100
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND LOWER(pr.drug) LIKE '%chlorthalidone%'
      OR LOWER(pr.drug) LIKE '%indapamide%'
      OR LOWER(pr.drug) LIKE '%metolazone%'
      OR LOWER(pr.drug) LIKE '%bendroflumethiazide%'
)
SELECT
  PERCENTILE_CONT(duration_days, 0.25) OVER() AS q1_days,
  PERCENTILE_CONT(duration_days, 0.75) OVER() AS q3_days,
  PERCENTILE_CONT(duration_days, 0.75) OVER() - PERCENTILE_CONT(duration_days, 0.25) OVER() AS iqr_days
FROM cohort;