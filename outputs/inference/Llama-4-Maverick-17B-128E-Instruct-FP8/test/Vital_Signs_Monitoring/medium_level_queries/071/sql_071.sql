WITH spO2_itemid AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE label LIKE '%SpO2%' OR label LIKE '%Saturation%'
),
mean_spO2 AS (
  SELECT ce.stay_id, AVG(ce.valuenum) AS mean_spO2
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN spO2_itemid si ON ce.itemid = si.itemid
  WHERE ce.valuenum IS NOT NULL AND ce.valuenum BETWEEN 0 AND 100
  GROUP BY ce.stay_id
),
filtered_stays AS (
  SELECT ie.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON ie.subject_id = p.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 38 AND 48
)
SELECT 
  COUNT(CASE WHEN ms.mean_spO2 <= 92 THEN 1 END) / COUNT(*) AS percentile
FROM mean_spO2 ms
JOIN filtered_stays fs ON ms.stay_id = fs.stay_id;