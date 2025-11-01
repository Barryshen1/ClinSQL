WITH filtered_patients AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 90 AND 100
),
thiazide_prescriptions AS (
  SELECT
    fp.hadm_id,
    fp.dischtime,
    pr.starttime,
    pr.stoptime,
    TIMESTAMP_DIFF(
      COALESCE(pr.stoptime, fp.dischtime),
      pr.starttime,
      SECOND
    ) / 86400.0 AS duration_days
  FROM filtered_patients fp
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON fp.subject_id = pr.subject_id AND fp.hadm_id = pr.hadm_id
  WHERE 
    LOWER(pr.drug) LIKE '%hydrochlorothiazide%'
    OR LOWER(pr.drug) LIKE '%chlorthalidone%'
    OR LOWER(pr.drug) LIKE '%indapamide%'
    OR LOWER(pr.drug) LIKE '%metolazone%'
    AND COALESCE(pr.stoptime, fp.dischtime) >= pr.starttime
)
SELECT
  APPROX_QUANTILES(duration_days, 1000)[OFFSET(750)] 
  - APPROX_QUANTILES(duration_days, 1000)[OFFSET(250)] AS iqr
FROM thiazide_prescriptions;