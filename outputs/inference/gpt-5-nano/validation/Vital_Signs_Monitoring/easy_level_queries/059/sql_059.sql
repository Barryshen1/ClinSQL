WITH Cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
),
SpO2Events AS (
  SELECT
    c.hadm_id,
    ce.charttime,
    ce.valuenum
  FROM Cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.hadm_id = c.hadm_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE ce.charttime >= c.admittime
    AND ce.charttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
    -- filter for SpO2-related measurements
    AND (
      LOWER(di.label) LIKE '%spo2%'
      OR LOWER(di.label) LIKE '%oxygen saturation%'
    )
),
FirstSpO2 AS (
  SELECT
    hadm_id,
    MIN(charttime) AS first_charttime
  FROM SpO2Events
  GROUP BY hadm_id
)
SELECT
  STDDEV_SAMP(spo2.valuenum) AS spo2_stddev
FROM FirstSpO2 f
JOIN `physionet-data.mimiciv_3_1_icu.chartevents` spo2
  ON spo2.hadm_id = f.hadm_id
  AND spo2.charttime = f.first_charttime
JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
  ON spo2.itemid = di.itemid
WHERE (
    LOWER(di.label) LIKE '%spo2%'
    OR LOWER(di.label) LIKE '%oxygen saturation%'
  )
  AND spo2.valuenum IS NOT NULL;