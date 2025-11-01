WITH
-- Get the itemid for respiratory rate (assuming 220210 is correct; verify in d_items)
respiratory_rate_item AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE label = 'Respiratory Rate'
),

-- Filter for female patients aged 38-48
target_patients AS (
  SELECT subject_id, anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 38 AND 48
),

-- Get ICU stays for target patients
icu_stays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime,
    TIMESTAMP_ADD(s.intime, INTERVAL 24 HOUR) AS first_24h_end
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN target_patients p ON s.subject_id = p.subject_id
),

-- Get respiratory rate measurements in the first 24 hours
respiratory_rates AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.charttime,
    c.valuenum AS respiratory_rate
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN icu_stays s ON c.subject_id = s.subject_id AND c.hadm_id = s.hadm_id AND c.stay_id = s.stay_id
  JOIN respiratory_rate_item r ON c.itemid = r.itemid
  WHERE c.charttime BETWEEN s.intime AND s.first_24h_end
    AND c.valuenum IS NOT NULL
)

-- Calculate the maximum respiratory rate per patient in the first 24 hours
SELECT
  p.subject_id,
  p.anchor_age,
  MAX(r.respiratory_rate) AS max_respiratory_rate_24h
FROM target_patients p
JOIN respiratory_rates r ON p.subject_id = r.subject_id
GROUP BY p.subject_id, p.anchor_age
ORDER BY max_respiratory_rate_24h DESC;