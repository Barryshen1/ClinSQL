WITH first_rr AS (
  SELECT
    c.stay_id,
    c.valuenum,
    ROW_NUMBER() OVER (PARTITION BY c.stay_id ORDER BY c.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON c.stay_id = i.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON i.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
    AND c.itemid = 220210
    AND c.valuenum IS NOT NULL
)
SELECT STDDEV(valuenum) AS std_dev
FROM first_rr
WHERE rn = 1;