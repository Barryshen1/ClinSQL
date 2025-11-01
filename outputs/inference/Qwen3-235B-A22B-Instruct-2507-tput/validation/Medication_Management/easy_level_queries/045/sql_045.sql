WITH dapt_prescriptions AS (
  SELECT
    p.subject_id,
    pr.drug,
    pr.starttime,
    pr.stoptime,
    DATETIME_DIFF(pr.stoptime, pr.starttime, SECOND) / (24 * 3600.0) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON pr.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 57 AND 67
    AND LOWER(pr.drug) IN (
      'aspirin', 'asa',
      'clopidogrel',
      'prasugrel',
      'ticagrelor'
    )
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND pr.stoptime >= pr.starttime
),
iqr_calc AS (
  SELECT
    APPROX_QUANTILES(duration_days, 1000)[OFFSET(250)] AS q1,
    APPROX_QUANTILES(duration_days, 1000)[OFFSET(750)] AS q3
  FROM dapt_prescriptions
)
SELECT
  q3 - q1 AS iqr_duration_days
FROM iqr_calc;