WITH
-- Filter male patients aged 77-87
eligible_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 77 AND 87
),

-- Get first SpO2 measurement for each patient during ICU stay
first_spo2 AS (
  SELECT
    ce.subject_id,
    ce.valuenum AS spo2_value,
    ROW_NUMBER() OVER (PARTITION BY ce.subject_id ORDER BY ce.charttime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  JOIN
    eligible_patients ep ON ce.subject_id = ep.subject_id
  WHERE
    di.label = 'SpO2'  -- or use itemid = 220277 directly if known
    AND ce.valuenum IS NOT NULL
)

-- Calculate standard deviation of first SpO2 values
SELECT
  STDDEV(spo2_value) AS stddev_spo2
FROM
  first_spo2
WHERE
  rn = 1  -- Only the first measurement per patient
;