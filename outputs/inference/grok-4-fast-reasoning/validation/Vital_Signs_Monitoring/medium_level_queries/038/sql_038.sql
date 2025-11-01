WITH qualifying_stays AS (
  SELECT DISTINCT i.stay_id, i.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 66 AND 76
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
      WHERE c.subject_id = i.subject_id
        AND c.stay_id = i.stay_id
        AND c.itemid = 720
        AND c.charttime BETWEEN i.intime AND i.outtime
    )
),
bp_data AS (
  SELECT cb.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` cb
  INNER JOIN qualifying_stays qs
    ON cb.stay_id = qs.stay_id
  WHERE cb.itemid IN (51, 442, 220045)
    AND cb.valuenum IS NOT NULL
    AND cb.charttime >= qs.intime
    AND cb.charttime <= DATETIME_ADD(qs.intime, INTERVAL 6 HOUR)
)
SELECT
  PERCENTILE_CONT(valuenum, 0.75) - PERCENTILE_CONT(valuenum, 0.25) AS iqr
FROM bp_data
LIMIT 1;