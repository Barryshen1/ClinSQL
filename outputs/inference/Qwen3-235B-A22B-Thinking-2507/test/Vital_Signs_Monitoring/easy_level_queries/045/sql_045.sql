WITH cohort AS (
  SELECT 
    icu.stay_id,
    p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year) AS age_at_icu
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year)) BETWEEN 51 AND 61
),
first_rr AS (
  SELECT 
    ce.stay_id,
    ce.valuenum AS rr,
    ROW_NUMBER() OVER (
      PARTITION BY ce.stay_id 
      ORDER BY ce.charttime ASC
    ) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN cohort c
    ON ce.stay_id = c.stay_id
  WHERE ce.itemid = 220210  -- Standard respiratory rate itemid
    AND ce.valuenum IS NOT NULL
)
SELECT 
  STDDEV(rr) AS sd_first_rr
FROM first_rr
WHERE rn = 1;