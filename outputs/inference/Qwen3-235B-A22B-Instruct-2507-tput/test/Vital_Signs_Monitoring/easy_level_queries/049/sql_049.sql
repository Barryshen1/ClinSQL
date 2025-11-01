WITH map_item AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu`.d_items
  WHERE LOWER(label) LIKE '%mean%arterial%pressure%'
     OR LOWER(label) = 'map'
     OR LOWER(label) LIKE '%map%'
),
patient_ages AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays i
    ON p.subject_id = i.subject_id
),
map_first_24h AS (
  SELECT
    ce.stay_id,
    AVG(ce.valuenum) AS mean_map_24h
  FROM `physionet-data.mimiciv_3_1_icu`.chartevents ce
  INNER JOIN map_item mi ON ce.itemid = mi.itemid
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays i ON ce.stay_id = i.stay_id
  INNER JOIN patient_ages pa ON i.subject_id = pa.subject_id
  WHERE
    ce.valuenum IS NOT NULL
    AND ce.charttime >= i.intime
    AND ce.charttime <= DATETIME_ADD(i.intime, INTERVAL 24 HOUR)
    AND pa.age_at_admission BETWEEN 85 AND 95
    AND pa.gender = 'M'
  GROUP BY ce.stay_id
)
SELECT
  STDDEV(mean_map_24h) AS std_dev_mean_map_first_24h
FROM map_first_24h;