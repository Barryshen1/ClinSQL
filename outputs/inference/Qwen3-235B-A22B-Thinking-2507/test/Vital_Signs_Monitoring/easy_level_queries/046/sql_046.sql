WITH cohort AS (
  SELECT 
    icu.stay_id,
    icu.intime,
    p.anchor_age,
    p.anchor_year
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year) BETWEEN 37 AND 47
),
spo2_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%spo2%'
     OR (LOWER(label) LIKE '%saturation%' AND LOWER(label) NOT LIKE '%inspired%')
),
first_spo2 AS (
  SELECT 
    stay_id,
    spo2_value
  FROM (
    SELECT 
      c.stay_id,
      ce.valuenum AS spo2_value,
      ROW_NUMBER() OVER (
        PARTITION BY c.stay_id 
        ORDER BY ce.charttime
      ) AS rn
    FROM cohort c
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
      ON c.stay_id = ce.stay_id
    INNER JOIN spo2_items si
      ON ce.itemid = si.itemid
    WHERE ce.charttime >= c.intime
      AND ce.valuenum IS NOT NULL
      AND ce.valuenum > 0
      AND ce.valuenum <= 100
  )
  WHERE rn = 1
)
SELECT 
  APPROX_QUANTILES(spo2_value, 1000)[OFFSET(750)] 
  - APPROX_QUANTILES(spo2_value, 1000)[OFFSET(250)] AS iqr
FROM first_spo2;