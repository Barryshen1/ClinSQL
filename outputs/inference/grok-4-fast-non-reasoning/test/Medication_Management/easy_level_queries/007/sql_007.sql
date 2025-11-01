WITH cohort_prescriptions AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    pr.starttime,
    pr.stoptime,
    DATE_DIFF(DATE(pr.stoptime), DATE(pr.starttime), DAY) AS duration_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  ON 
    p.subject_id = pr.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 90 AND 100
    AND (LOWER(pr.drug) LIKE '%hydrochlorothiazide%' OR LOWER(pr.drug) LIKE '%chlorthalidone%')
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND pr.stoptime > pr.starttime
    AND EXTRACT(YEAR FROM pr.starttime) >= 2100
    AND DATE_DIFF(DATE(pr.stoptime), DATE(pr.starttime), DAY) > 0
)

SELECT 
  APPROX_QUANTILES(duration_days, 4)[OFFSET(1)] AS q1,
  APPROX_QUANTILES(duration_days, 4)[OFFSET(3)] AS q3,
  (APPROX_QUANTILES(duration_days, 4)[OFFSET(3)] - APPROX_QUANTILES(duration_days, 4)[OFFSET(1)]) AS iqr_days
FROM 
  cohort_prescriptions;