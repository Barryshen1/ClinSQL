WITH map_avg AS (
  SELECT ce.stay_id, AVG(ce.valuenum) AS avg_map
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie ON ce.stay_id = ie.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE di.label = 'Mean Arterial Pressure'
  AND ce.charttime BETWEEN ie.intime AND TIMESTAMP_ADD(ie.intime, INTERVAL 24 HOUR)
  GROUP BY ce.stay_id
),
patient_info AS (
  SELECT ie.stay_id, p.gender, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON ie.subject_id = p.subject_id
),
filtered_map_avg AS (
  SELECT ma.avg_map
  FROM map_avg ma
  JOIN patient_info pi ON ma.stay_id = pi.stay_id
  WHERE pi.gender = 'M' AND pi.anchor_age BETWEEN 39 AND 49
)
SELECT SAFE_DIVIDE(COUNTIF(avg_map <= 75), COUNT(*)) AS percentile
FROM filtered_map_avg;