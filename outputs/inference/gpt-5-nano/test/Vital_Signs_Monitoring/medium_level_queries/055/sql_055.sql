WITH per_stay AS (
  SELECT
    i.stay_id,
    i.subject_id,
    i.hadm_id,
    AVG(ce.valuenum) AS spo2_first24_avg
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = i.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ce.subject_id = i.subject_id
   AND ce.hadm_id = i.hadm_id
   AND ce.stay_id = i.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON di.itemid = ce.itemid
  WHERE
    LOWER(p.gender) IN ('female', 'f')
    AND p.anchor_age BETWEEN 87 AND 97
    -- SpO2 related items
    AND (LOWER(di.label) LIKE '%spo2%' OR LOWER(di.label) LIKE '%oxygen saturation%')
    -- First 24 hours of ICU stay
    AND ce.charttime >= i.intime
    AND ce.charttime < TIMESTAMP_ADD(i.intime, INTERVAL 24 HOUR)
    -- Valid numeric readings
    AND ce.valuenum IS NOT NULL
  GROUP BY
    i.stay_id, i.subject_id, i.hadm_id
),
dist AS (
  SELECT spo2_first24_avg
  FROM per_stay
  WHERE spo2_first24_avg IS NOT NULL
)
SELECT
  (SELECT COUNT(*) FROM dist WHERE spo2_first24_avg <= 88) / NULLIF((SELECT COUNT(*) FROM dist), 0) * 100 AS percentile_88
;