WITH patient_stays AS (
  SELECT
    i.stay_id
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 39 AND 49
),
map_averages AS (
  SELECT
    i.stay_id,
    AVG(c.valuenum) AS avg_map
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON i.stay_id = c.stay_id
  WHERE
    c.itemid = 51
    AND c.charttime BETWEEN i.intime AND DATETIME_ADD(i.intime, INTERVAL 24 HOUR)
    AND c.valuenum IS NOT NULL
  GROUP BY
    i.stay_id
)
SELECT
  (COUNTIF(avg_map <= 75) * 100.0) / NULLIF(COUNT(*), 0) AS percentile
FROM
  map_averages
WHERE
  stay_id IN (SELECT stay_id FROM patient_stays);