WITH icu_stays_with_age AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    p.gender,
    -- Calculate age at ICU admission using anchor_year and anchor_age
    EXTRACT(YEAR FROM i.intime) - (p.anchor_year - p.anchor_age) AS age_at_icu
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE
    p.gender = 'M' -- Male patients
    AND EXTRACT(YEAR FROM i.intime) - (p.anchor_year - p.anchor_age) BETWEEN 38 AND 48 -- Age 38-48
),
map_measurements AS (
  SELECT
    cs.subject_id,
    cs.hadm_id,
    cs.stay_id,
    ce.valuenum AS map_value
  FROM
    icu_stays_with_age cs
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON cs.subject_id = ce.subject_id
    AND cs.hadm_id = ce.hadm_id
    AND cs.stay_id = ce.stay_id
  WHERE
    ce.itemid IN (6702, 4561) -- Common MAP itemids (Arterial Mean and Noninvasive Mean)
    AND ce.valuenum IS NOT NULL -- Ensure numeric value exists
),
average_map_per_stay AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    AVG(map_value) AS avg_map
  FROM
    map_measurements
  GROUP BY
    subject_id, hadm_id, stay_id
),
proportion_calculation AS (
  SELECT
    COUNT(CASE WHEN avg_map <= 60 THEN 1 END) * 1.0 / COUNT(*) AS proportion
  FROM
    average_map_per_stay
)
SELECT
  proportion
FROM
  proportion_calculation;