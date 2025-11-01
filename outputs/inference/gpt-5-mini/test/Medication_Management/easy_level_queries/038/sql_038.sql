WITH cohort_prescriptions AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.starttime AS pres_start,
    pr.stoptime AS pres_stop,
    a.admittime,
    a.dischtime,
    GREATEST(pr.starttime, a.admittime) AS med_start,
    LEAST(COALESCE(pr.stoptime, a.dischtime), a.dischtime) AS med_end,
    SAFE_DIVIDE(
      TIMESTAMP_DIFF(
        LEAST(COALESCE(pr.stoptime, a.dischtime), a.dischtime),
        GREATEST(pr.starttime, a.admittime),
        SECOND
      ),
      86400.0
    ) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON pr.subject_id = a.subject_id AND pr.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON pr.subject_id = p.subject_id
  WHERE LOWER(pr.drug) LIKE '%digoxin%'
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 36 AND 46
    AND pr.hadm_id IS NOT NULL
)
SELECT
  q[OFFSET(25)] AS p25_days,
  q[OFFSET(75)] AS p75_days,
  q[OFFSET(75)] - q[OFFSET(25)] AS iqr_days,
  n_prescriptions
FROM (
  SELECT
    APPROX_QUANTILES(duration_days, 100) AS q,
    COUNT(*) AS n_prescriptions
  FROM cohort_prescriptions
  WHERE duration_days IS NOT NULL AND duration_days > 0
);