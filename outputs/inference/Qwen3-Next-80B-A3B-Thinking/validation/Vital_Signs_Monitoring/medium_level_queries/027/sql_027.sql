WITH filtered_stays AS (
  SELECT 
    i.stay_id,
    p.anchor_age,
    a.admittime,
    p.anchor_year,
    p.gender
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON i.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 80 AND 90
),
avg_hr_per_stay AS (
  SELECT 
    f.stay_id,
    AVG(c.valuenum) AS avg_hr
  FROM filtered_stays f
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c 
    ON f.stay_id = c.stay_id
  WHERE c.itemid = 211
    AND c.valuenum IS NOT NULL
  GROUP BY f.stay_id
)
SELECT 
  (COUNTIF(avg_hr <= 110) * 100.0) / NULLIF(COUNT(*), 0) AS percentile
FROM avg_hr_per_stay;