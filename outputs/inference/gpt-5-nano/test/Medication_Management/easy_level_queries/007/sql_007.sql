WITH thiazide_prescriptions AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime,
    p.drug,
    TIMESTAMP_DIFF(p.stoptime, p.starttime, SECOND) / 86400.0 AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON a.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 90 AND 100
    AND p.starttime >= a.admittime
    AND p.stoptime <= a.dischtime
    AND p.stoptime IS NOT NULL
    AND (
      LOWER(p.drug) LIKE '%hydrochlorothiazide%' OR
      LOWER(p.drug) LIKE '%chlorthalidone%' OR
      LOWER(p.drug) LIKE '%chlortalidone%' OR
      LOWER(p.drug) LIKE '%metolazone%' OR
      LOWER(p.drug) LIKE '%indapamide%' OR
      LOWER(p.drug) LIKE '%bendroflumethiazide%' OR
      LOWER(p.drug) LIKE '%thiazide%'
    )
)
SELECT
  PERCENTILE_CONT(duration_days, 0.25) OVER() AS q1_days,
  PERCENTILE_CONT(duration_days, 0.75) OVER() AS q3_days,
  (PERCENTILE_CONT(duration_days, 0.75) OVER() - PERCENTILE_CONT(duration_days, 0.25) OVER()) AS iqr_days
FROM thiazide_prescriptions
LIMIT 1;