WITH amio_durations AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    TIMESTAMP_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
     AND p.hadm_id = a.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON p.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 59 AND 69
    AND LOWER(p.drug) LIKE '%amiodarone%'
    -- ensure prescription falls within the admission:
    AND p.starttime BETWEEN a.admittime AND a.dischtime
    AND p.stoptime  BETWEEN a.admittime AND a.dischtime
    -- meaningful positive duration
    AND TIMESTAMP_DIFF(p.stoptime, p.starttime, DAY) > 0
),
quantiles AS (
  SELECT
    APPROX_QUANTILES(duration_days, 100) AS pctiles
  FROM
    amio_durations
)
SELECT
  pctiles[OFFSET(75)] AS p75,
  pctiles[OFFSET(25)] AS p25,
  pctiles[OFFSET(75)] - pctiles[OFFSET(25)] AS iqr_days
FROM
  quantiles;