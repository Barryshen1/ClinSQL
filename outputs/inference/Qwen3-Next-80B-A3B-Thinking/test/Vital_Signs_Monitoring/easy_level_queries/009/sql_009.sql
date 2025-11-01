SELECT percentile_75
FROM (
  SELECT
    PERCENTILE_CONT(valuenum, 0.75) OVER (ORDER BY valuenum) AS percentile_75
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON ce.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 86 AND 96
    AND ce.itemid IN (220045, 223761)
    AND ce.charttime BETWEEN icu.intime AND icu.intime + INTERVAL 24 HOUR
    AND ce.valuenum IS NOT NULL
)
LIMIT 1;