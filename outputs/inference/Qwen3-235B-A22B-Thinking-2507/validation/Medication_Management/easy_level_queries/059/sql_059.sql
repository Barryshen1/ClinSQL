WITH eligible_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 38 AND 48
),
arb_prescriptions AS (
  SELECT
    ea.hadm_id,
    TIMESTAMP_DIFF(
      LEAST(p.stoptime, ea.dischtime),
      GREATEST(p.starttime, ea.admittime),
      SECOND
    ) / (24 * 60 * 60) AS duration_days
  FROM
    eligible_admissions ea
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON ea.hadm_id = p.hadm_id
  WHERE
    p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
    AND p.starttime < ea.dischtime
    AND p.stoptime > ea.admittime
    AND (
      LOWER(p.drug) LIKE '%losartan%' OR
      LOWER(p.drug) LIKE '%valsartan%' OR
      LOWER(p.drug) LIKE '%irbesartan%' OR
      LOWER(p.drug) LIKE '%candesartan%' OR
      LOWER(p.drug) LIKE '%telmisartan%' OR
      LOWER(p.drug) LIKE '%olmesartan%' OR
      LOWER(p.drug) LIKE '%eprosartan%' OR
      LOWER(p.drug) LIKE '%azilsartan%' OR
      LOWER(p.drug) LIKE '%cozaar%' OR
      LOWER(p.drug) LIKE '%diovan%' OR
      LOWER(p.drug) LIKE '%avapro%' OR
      LOWER(p.drug) LIKE '%atacand%' OR
      LOWER(p.drug) LIKE '%micardis%' OR
      LOWER(p.drug) LIKE '%benicar%' OR
      LOWER(p.drug) LIKE '%teveten%' OR
      LOWER(p.drug) LIKE '%edarbi%'
    )
)
SELECT
  APPROX_QUANTILES(duration_days, 1000)[OFFSET(750)] AS percentile_75
FROM
  arb_prescriptions;