WITH
-- Get female patients aged 87-97 at ICU admission
female_patients AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    p.anchor_year,
    -- Calculate age at ICU admission (approximate)
    p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year) AS age_at_icu_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
  ON
    p.subject_id = i.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year) BETWEEN 87 AND 97
),

-- Get first 24-hour SBP measurements for each ICU stay
first_24h_sbp AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    -- Calculate average SBP in first 24 hours
    AVG(ce.valuenum) AS avg_sbp_24h
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON
    i.subject_id = ce.subject_id
    AND i.stay_id = ce.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
  ON
    ce.itemid = di.itemid
  WHERE
    ce.itemid = 220050 -- SBP itemid
    AND ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 24 HOUR)
    AND i.subject_id IN (SELECT subject_id FROM female_patients)
  GROUP BY
    i.subject_id, i.hadm_id, i.stay_id, i.intime
)

-- Calculate percentile for SBP = 150 mmHg
SELECT
  PERCENT_RANK() OVER (ORDER BY avg_sbp_24h) AS percentile
FROM
  first_24h_sbp
WHERE
  avg_sbp_24h = 150
LIMIT 1;