WITH first_pH AS (
  SELECT
    c.valuenum,
    ROW_NUMBER() OVER (PARTITION BY i.stay_id ORDER BY c.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON p.subject_id = i.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON i.stay_id = c.stay_id
  WHERE p.gender = 'F'
    AND c.itemid = 5082
    AND c.charttime BETWEEN i.intime AND i.outtime
    AND c.valuenum IS NOT NULL
)
SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY valuenum) AS median_pH
FROM first_pH
WHERE rn = 1;