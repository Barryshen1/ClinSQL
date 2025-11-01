WITH filtered_prescriptions AS (
  SELECT
    CASE
      WHEN pr.stoptime IS NULL 
        THEN TIMESTAMP_DIFF(a.dischtime, pr.starttime, SECOND) / 86400.0
      ELSE TIMESTAMP_DIFF(pr.stoptime, pr.starttime, SECOND) / 86400.0
    END AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON a.hadm_id = pr.hadm_id
  WHERE
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 36 AND 46
    AND LOWER(pr.drug) LIKE '%digoxin%'
    AND pr.starttime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND (
      (pr.stoptime IS NOT NULL AND pr.stoptime >= pr.starttime)
      OR (pr.stoptime IS NULL AND a.dischtime >= pr.starttime)
    )
)
SELECT
  APPROX_QUANTILES(duration_days, 1000)[OFFSET(750)] 
  - APPROX_QUANTILES(duration_days, 1000)[OFFSET(250)] AS iqr
FROM filtered_prescriptions
WHERE duration_days >= 0;