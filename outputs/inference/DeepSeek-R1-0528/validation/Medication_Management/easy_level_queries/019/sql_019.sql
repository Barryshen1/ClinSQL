WITH filtered_prescriptions AS (
  SELECT
    TIMESTAMP_DIFF(p.stoptime, p.starttime, MICROSECOND) / 86400000000.0 AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON p.subject_id = pt.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON p.hadm_id = adm.hadm_id AND p.subject_id = adm.subject_id
  WHERE
    -- Filter for males
    pt.gender = 'M'
    -- Calculate age at admission and filter between 58-68
    AND pt.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pt.anchor_year) BETWEEN 58 AND 68
    -- Identify heparin/enoxaparin prescriptions
    AND (LOWER(p.drug) LIKE '%heparin%' OR LOWER(p.drug) LIKE '%enoxaparin%')
    -- Exclude invalid time entries
    AND p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
    AND p.stoptime > p.starttime
)
SELECT
  APPROX_QUANTILES(duration_days, 100)[OFFSET(50)] AS median_duration_days
FROM
  filtered_prescriptions;