WITH
-- Get all ICU stays for 56-year-old males
icu_stays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    s.hadm_id = a.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    s.subject_id = p.subject_id
  WHERE
    p.anchor_age = 56
    AND p.gender = 'M'
),

-- Get potassium measurements for these stays
potassium_measurements AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.charttime,
    c.valuenum,
    c.valueuom,
    d.label
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` d
  ON
    c.itemid = d.itemid
  JOIN
    icu_stays s
  ON
    c.subject_id = s.subject_id
    AND c.hadm_id = s.hadm_id
    AND c.stay_id = s.stay_id
  WHERE
    (d.label LIKE '%Potassium%' OR d.label LIKE '%K%') -- Common labels for potassium
    AND c.valuenum IS NOT NULL
    AND c.valueuom = 'mEq/L' -- Ensure correct units
),

-- Get peak potassium per stay
peak_potassium AS (
  SELECT
    stay_id,
    MAX(valuenum) AS peak_potassium
  FROM
    potassium_measurements
  GROUP BY
    stay_id
)

-- Calculate standard deviation of peak potassium values
SELECT
  STDDEV(peak_potassium) AS stddev_peak_potassium
FROM
  peak_potassium
WHERE
  peak_potassium IS NOT NULL;