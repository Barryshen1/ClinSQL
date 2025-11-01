WITH spo2_itemids AS (
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%spo2%' OR LOWER(label) LIKE '%o2 sat%'
),
eligible_stays AS (
  SELECT 
    icu.subject_id,
    icu.stay_id,
    icu.hadm_id,
    pat.gender,
    pat.anchor_age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 37 AND 47
),
first_spo2 AS (
  SELECT 
    es.*,
    ce.charttime,
    ce.valuenum AS spo2
  FROM eligible_stays es
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.subject_id = es.subject_id
    AND ce.hadm_id = es.hadm_id
    AND ce.stay_id = es.stay_id
  INNER JOIN spo2_itemids si
    ON ce.itemid = si.itemid
  WHERE ce.charttime >= (
    SELECT intime FROM `physionet-data.mimiciv_3_1_icu.icustays` icu3 WHERE icu3.stay_id = es.stay_id
  )
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 0 AND 100
  QUALIFY ROW_NUMBER() OVER (PARTITION BY es.stay_id ORDER BY ce.charttime ASC) = 1
)
SELECT
  PERCENTILE_CONT(spo2, 0.75) AS q75,
  PERCENTILE_CONT(spo2, 0.25) AS q25,
  (PERCENTILE_CONT(spo2, 0.75) - PERCENTILE_CONT(spo2, 0.25)) AS iqr
FROM first_spo2;