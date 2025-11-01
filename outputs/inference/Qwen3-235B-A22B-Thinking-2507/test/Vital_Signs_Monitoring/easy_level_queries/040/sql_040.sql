WITH filtered_patients AS (
  SELECT 
    i.stay_id,
    i.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year) BETWEEN 55 AND 65
),
first_map AS (
  SELECT 
    c.stay_id,
    c.valuenum,
    ROW_NUMBER() OVER (
      PARTITION BY c.stay_id 
      ORDER BY c.charttime, c.storetime
    ) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  INNER JOIN filtered_patients f
    ON c.stay_id = f.stay_id
  WHERE c.itemid = 220052
    AND c.charttime >= f.intime
    AND c.valuenum IS NOT NULL
)
SELECT STDDEV(valuenum) AS sd_first_map
FROM first_map
WHERE rn = 1;