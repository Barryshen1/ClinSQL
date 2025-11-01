SELECT
  MIN(ce.valuenum) AS min_heart_rate
FROM
  `physionet-data.mimiciv_3_1_hosp.patients` p
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON p.subject_id = a.subject_id
INNER JOIN
  `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON a.subject_id = ce.subject_id
  AND a.hadm_id = ce.hadm_id
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 44 AND 54
  AND ce.itemid = 220045  -- Heart Rate itemid
  AND ce.valuenum IS NOT NULL
  AND ce.charttime >= a.admittime
  AND ce.charttime < DATETIME_ADD(a.admittime, INTERVAL 24 HOUR);