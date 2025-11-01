WITH eligible_prescriptions AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
   AND p.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON p.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 51 AND 61
    AND p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
    AND p.starttime <= p.stoptime
    AND p.starttime >= a.admittime
    AND p.stoptime <= a.dischtime
    AND REGEXP_CONTAINS(LOWER(p.drug), r'(hydralazine|isosorbide dinitrate|bidil)')
),
durations AS (
  SELECT
    subject_id,
    hadm_id,
    (TIMESTAMP_DIFF(stoptime, starttime, SECOND) / 86400.0) AS duration_days
  FROM eligible_prescriptions
),
per_admission_max AS (
  SELECT
    subject_id,
    hadm_id,
    MAX(duration_days) AS max_duration_days
  FROM durations
  GROUP BY subject_id, hadm_id
),
ranked AS (
  SELECT
    subject_id,
    hadm_id,
    max_duration_days,
    RANK() OVER (ORDER BY max_duration_days DESC) AS rnk
  FROM per_admission_max
)
SELECT
  subject_id,
  hadm_id,
  max_duration_days
FROM ranked
WHERE rnk = 1
ORDER BY max_duration_days DESC;