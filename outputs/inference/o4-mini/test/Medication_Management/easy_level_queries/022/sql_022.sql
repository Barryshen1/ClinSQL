WITH female_cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      USING(subject_id)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
),
ccbs AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.starttime,
    pr.stoptime,
    SAFE_DIVIDE(
      TIMESTAMP_DIFF(pr.stoptime, pr.starttime, SECOND),
      86400.0
    ) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    JOIN female_cohort fc
      USING(subject_id, hadm_id)
  WHERE
    pr.starttime >= fc.admittime
    AND pr.stoptime <= fc.dischtime
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND pr.stoptime > pr.starttime
    AND LOWER(pr.drug) LIKE '%dipine%'
)
SELECT
  APPROX_QUANTILES(duration_days, 2)[OFFSET(1)] AS median_duration_days
FROM
  ccbs;