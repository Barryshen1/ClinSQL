WITH male_icu_patients AS (
  -- Get male ICU patients aged 55-65
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    i.hadm_id,
    i.stay_id,
    i.intime AS icu_admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
  ON
    p.subject_id = i.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 55 AND 65
),

first_map AS (
  -- Get the first MAP measurement for each ICU stay
  SELECT
    m.subject_id,
    m.hadm_id,
    m.stay_id,
    ce.charttime,
    ce.valuenum AS first_map_value
  FROM
    male_icu_patients m
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON
    m.subject_id = ce.subject_id
    AND m.hadm_id = ce.hadm_id
    AND m.stay_id = ce.stay_id
  WHERE
    ce.itemid = 220050  -- MAP itemid
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY m.stay_id ORDER BY ce.charttime) = 1
)

-- Calculate the standard deviation of first MAP values
SELECT
  STDDEV(first_map_value) AS sd_first_map
FROM
  first_map;