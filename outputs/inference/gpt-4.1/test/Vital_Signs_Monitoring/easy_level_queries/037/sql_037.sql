WITH map_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%mean arterial pressure%'
     OR LOWER(label) LIKE '%map%'
),
female_elderly_icu AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 89 AND 99
)
SELECT
  AVG(ce.valuenum) AS avg_map_first_24h
FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
JOIN female_elderly_icu fe
  ON ce.subject_id = fe.subject_id
  AND ce.hadm_id = fe.hadm_id
  AND ce.stay_id = fe.stay_id
JOIN map_itemids mi
  ON ce.itemid = mi.itemid
WHERE ce.valuenum IS NOT NULL
  AND ce.charttime >= fe.intime
  AND ce.charttime < TIMESTAMP_ADD(fe.intime, INTERVAL 24 HOUR);