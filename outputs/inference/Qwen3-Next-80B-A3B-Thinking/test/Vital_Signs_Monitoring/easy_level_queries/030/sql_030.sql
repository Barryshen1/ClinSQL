WITH earliest_charttime AS (
  SELECT 
    c.stay_id,
    MIN(c.charttime) AS first_charttime
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` d ON c.itemid = d.itemid
  WHERE d.label = 'Heart Rate'
  GROUP BY c.stay_id
)
SELECT MIN(c.valuenum) AS min_first_hr
FROM earliest_charttime e
JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c 
  ON e.stay_id = c.stay_id AND e.first_charttime = c.charttime
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
  ON c.subject_id = p.subject_id
WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 38 AND 48;