WITH
-- Get female patients aged 73-83
female_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 73 AND 83
),

-- Get stays in step-down/IMC units
stepdown_stays AS (
  SELECT DISTINCT
    t.subject_id,
    t.hadm_id,
    i.stay_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.transfers` t
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i ON t.subject_id = i.subject_id AND t.hadm_id = i.hadm_id
  JOIN
    female_patients fp ON t.subject_id = fp.subject_id
  WHERE
    t.careunit IN ('Stepdown Unit', 'IMC')  -- Adjust based on actual careunit names in MIMIC-IV
),

-- Get MAP measurements for these stays
map_measurements AS (
  SELECT
    ce.stay_id,
    ce.valuenum AS map_value
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    stepdown_stays ss ON ce.subject_id = ss.subject_id AND ce.hadm_id = ss.hadm_id AND ce.stay_id = ss.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE
    di.label = 'Mean Arterial Pressure'  -- Confirm exact label in MIMIC-IV
    AND ce.valuenum IS NOT NULL
)

-- Calculate average MAP per stay
SELECT
  stay_id,
  AVG(map_value) AS avg_map_per_stay
FROM
  map_measurements
GROUP BY
  stay_id
ORDER BY
  stay_id;