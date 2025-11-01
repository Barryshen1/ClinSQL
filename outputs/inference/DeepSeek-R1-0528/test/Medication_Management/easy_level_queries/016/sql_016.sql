WITH filtered_prescriptions AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.drug,
    p.route,
    p.starttime,
    p.stoptime,
    -- Calculate age at admission
    pt.anchor_age + (EXTRACT(YEAR FROM a.admittime) - pt.anchor_year) AS age_at_admission,
    -- Compute duration in fractional days
    TIMESTAMP_DIFF(p.stoptime, p.starttime, HOUR) / 24.0 AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id AND p.hadm_id = a.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
      ON p.subject_id = pt.subject_id
  WHERE
    -- Filter for nitrate drugs
    (LOWER(p.drug) LIKE '%nitrate%'
      OR LOWER(p.drug) LIKE '%nitroglycerin%'
      OR LOWER(p.drug) LIKE '%isosorbide%')
    -- Filter for IV or oral routes
    AND (LOWER(p.route) LIKE '%iv%'
      OR LOWER(p.route) LIKE '%oral%'
      OR LOWER(p.route) LIKE '%po%'
      OR LOWER(p.route) LIKE '%by mouth%')
    -- Exclude invalid time ranges
    AND p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
    AND p.stoptime > p.starttime
    -- Filter age 76-86 at admission
    AND (pt.anchor_age + (EXTRACT(YEAR FROM a.admittime) - pt.anchor_year)) BETWEEN 76 AND 86
)
SELECT
  -- Calculate 25th percentile duration using approximate quantiles
  APPROX_QUANTILES(duration_days, 100)[OFFSET(25)] AS percentile_25_duration_days
FROM
  filtered_prescriptions;