WITH filtered_patients AS (
  SELECT i.stay_id, i.subject_id, i.hadm_id, i.intime, p.anchor_age, p.gender
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON i.subject_id = p.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 89 AND 99
),
map_measurements AS (
  SELECT fp.stay_id, c.valuenum, c.charttime, fp.intime
  FROM filtered_patients fp
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c ON fp.stay_id = c.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` d ON c.itemid = d.itemid
  WHERE d.label = 'Mean Arterial Pressure' AND c.charttime BETWEEN fp.intime AND TIMESTAMP_ADD(fp.intime, INTERVAL 24 HOUR)
)
SELECT AVG(valuenum) AS avg_map
FROM map_measurements;