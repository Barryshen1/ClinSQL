WITH first_admissions AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  QUALIFY ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) = 1
)
SELECT
  STDDEV_SAMP(los_days) AS sd_los_days
FROM first_admissions
WHERE gender = 'F'
  AND anchor_age BETWEEN 70 AND 80
  AND los_days IS NOT NULL;