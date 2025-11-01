WITH max_dbp AS (
  SELECT MAX(c.valuenum) AS max_dbp
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` d
    ON c.itemid = d.itemid
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON c.stay_id = i.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 71 AND 81
    AND d.label LIKE '%Diastolic%'
    AND c.valuenum IS NOT NULL
  GROUP BY c.stay_id
)
SELECT PERCENTILE_CONT(max_dbp, 0.5) OVER() AS median_max_dbp
FROM max_dbp
LIMIT 1;