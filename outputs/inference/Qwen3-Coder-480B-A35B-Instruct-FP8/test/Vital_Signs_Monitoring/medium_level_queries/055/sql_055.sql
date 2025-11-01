WITH cohort AS (
  SELECT ie.stay_id,
         ie.subject_id,
         ie.intime,
         ie.outtime,
         pat.anchor_age
  FROM physionet-data.mimiciv_3_1_icu.icustays ie
  JOIN physionet-data.mimiciv_3_1_hosp.patients pat
    ON ie.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 87 AND 97
),
spo2_itemid AS (
  SELECT itemid
  FROM physionet-data.mimiciv_3_1_icu.d_items
  WHERE LOWER(label) LIKE '%spo2%'
),
spo2_avg_first24 AS (
  SELECT ce.stay_id,
         AVG(ce.valuenum) AS avg_spo2
  FROM physionet-data.mimiciv_3_1_icu.chartevents ce
  JOIN cohort co
    ON ce.stay_id = co.stay_id
  JOIN spo2_itemid sp
    ON ce.itemid = sp.itemid
  WHERE ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 0 AND 100
    AND ce.charttime >= co.intime
    AND ce.charttime <= DATETIME_ADD(co.intime, INTERVAL 24 HOUR)
  GROUP BY ce.stay_id
),
percentile_calc AS (
  SELECT
    COUNTIF(avg_spo2 < 88) AS below_count,
    COUNT(*) AS total_count
  FROM spo2_avg_first24
)
SELECT
  CASE
    WHEN total_count = 0 THEN NULL
    ELSE (below_count * 100.0) / total_count
  END AS percentile
FROM percentile_calc;