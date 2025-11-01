WITH first_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 77 AND 87
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) = 1
)

SELECT
  APPROX_QUANTILES(los_days, 4)[OFFSET(1)] AS q1,
  APPROX_QUANTILES(los_days, 4)[OFFSET(3)] AS q3,
  APPROX_QUANTILES(los_days, 4)[OFFSET(3)] - APPROX_QUANTILES(los_days, 4)[OFFSET(1)] AS iqr
FROM
  first_admissions
WHERE
  los_days IS NOT NULL;