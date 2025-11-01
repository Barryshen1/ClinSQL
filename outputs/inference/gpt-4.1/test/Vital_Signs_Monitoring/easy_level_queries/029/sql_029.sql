WITH male_patients_62_72 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 62 AND 72
),
first_spo2 AS (
  SELECT
    ce.subject_id,
    ce.charttime,
    ce.valuenum AS spo2,
    ROW_NUMBER() OVER (PARTITION BY ce.subject_id ORDER BY ce.charttime ASC) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN male_patients_62_72 mp ON ce.subject_id = mp.subject_id
  WHERE ce.itemid IN (220277, 646)
    AND ce.valuenum IS NOT NULL
)
SELECT
  PERCENTILE_CONT(spo2, 0.75) OVER () - PERCENTILE_CONT(spo2, 0.25) OVER () AS spo2_iqr
FROM first_spo2
WHERE rn = 1;