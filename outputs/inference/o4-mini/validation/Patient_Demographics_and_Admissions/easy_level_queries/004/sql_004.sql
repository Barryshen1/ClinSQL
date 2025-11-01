WITH first_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
    AND a.admittime = (
      SELECT MIN(admittime)
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a2
      WHERE a2.subject_id = a.subject_id
    )
)
SELECT
  STDDEV_SAMP(los_days) AS sd_los_days
FROM
  first_admissions;