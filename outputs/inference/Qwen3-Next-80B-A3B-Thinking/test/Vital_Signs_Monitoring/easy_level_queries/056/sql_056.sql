WITH filtered_icustays AS (
  SELECT
    i.stay_id,
    i.intime,
    p.anchor_age,
    p.anchor_year,
    p.gender
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND (EXTRACT(YEAR FROM i.intime) - (p.anchor_year - p.anchor_age)) BETWEEN 46 AND 56
)
SELECT
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY c.valuenum) AS median_temperature
FROM filtered_icustays f
JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
  ON f.stay_id = c.stay_id
WHERE
  c.itemid = 223761
  AND c.charttime BETWEEN f.intime AND f.intime + INTERVAL 24 HOUR
  AND c.valuenum IS NOT NULL;