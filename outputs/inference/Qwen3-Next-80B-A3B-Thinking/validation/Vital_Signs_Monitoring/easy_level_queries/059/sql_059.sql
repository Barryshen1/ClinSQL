WITH first_spo2 AS (
  SELECT
    c.stay_id,
    c.valuenum,
    ROW_NUMBER() OVER (PARTITION BY c.stay_id ORDER BY c.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON c.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
    AND c.itemid = 220277
    AND c.charttime >= a.admittime
    AND c.valuenum IS NOT NULL
)
SELECT
  STDDEV(valuenum) AS std_dev_spo2
FROM first_spo2
WHERE rn = 1;