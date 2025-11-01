WITH target_prescriptions AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime,
    CAST(TIMESTAMP_DIFF(p.stoptime, p.starttime, SECOND) AS FLOAT64) / 86400.0 AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON p.subject_id = pt.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON p.subject_id = adm.subject_id
    AND p.hadm_id = adm.hadm_id
  WHERE pt.gender = 'F'
    -- include explicit ages 90-100; include anchor_age = 300 to capture de-identified >89 records (may include >100)
    AND (pt.anchor_age BETWEEN 90 AND 100 OR pt.anchor_age = 300)
    AND p.hadm_id IS NOT NULL
    AND p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
    AND p.stoptime > p.starttime
    -- ensure the prescription occurs during the hospital admission
    AND p.starttime BETWEEN adm.admittime AND adm.dischtime
    -- thiazide-like agents: chlorthalidone, indapamide, metolazone (case-insensitive)
    AND (
      LOWER(COALESCE(p.drug, '')) LIKE '%chlorthalidone%'
      OR LOWER(COALESCE(p.drug, '')) LIKE '%indapamide%'
      OR LOWER(COALESCE(p.drug, '')) LIKE '%metolazone%'
    )
)

SELECT
  quantiles[OFFSET(25)] AS p25_days,
  quantiles[OFFSET(75)] AS p75_days,
  SAFE_SUBTRACT(quantiles[OFFSET(75)], quantiles[OFFSET(25)]) AS iqr_days
FROM (
  SELECT APPROX_QUANTILES(duration_days, 100) AS quantiles
  FROM target_prescriptions
);