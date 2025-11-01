WITH map_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%mean arterial pressure%'
     OR LOWER(label) = 'map'
),
cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 55 AND 65
),
first_map AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    MIN(ce.charttime) AS first_map_time
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.subject_id = ce.subject_id
    AND c.stay_id = ce.stay_id
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= c.intime
  JOIN map_items mi
    ON ce.itemid = mi.itemid
  GROUP BY c.subject_id, c.hadm_id, c.stay_id
),
first_map_value AS (
  SELECT
    fm.subject_id,
    fm.hadm_id,
    fm.stay_id,
    ce.valuenum AS first_map
  FROM first_map fm
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON fm.subject_id = ce.subject_id
    AND fm.stay_id = ce.stay_id
    AND ce.valuenum IS NOT NULL
    AND ce.charttime = fm.first_map_time
  JOIN map_items mi
    ON ce.itemid = mi.itemid
)
SELECT
  STDDEV_SAMP(first_map) AS sd_first_map
FROM first_map_value;