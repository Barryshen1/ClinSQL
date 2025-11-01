WITH first_stays AS (
  SELECT 
    p.subject_id, 
    i.stay_id, 
    i.hadm_id, 
    i.intime,
    p.anchor_age + EXTRACT(YEAR FROM i.intime) - p.anchor_year AS age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'M'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime ASC) = 1
),
qualifying_stays AS (
  SELECT subject_id, stay_id, hadm_id
  FROM first_stays
  WHERE age >= 55 AND age <= 65
),
max_hr_per_patient AS (
  SELECT 
    qs.subject_id,
    MAX(c.valuenum) AS max_hr
  FROM qualifying_stays qs
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON c.subject_id = qs.subject_id
    AND c.hadm_id = qs.hadm_id
    AND c.stay_id = qs.stay_id
  WHERE c.itemid = 220045
    AND c.valuenum IS NOT NULL
    AND c.valuenum > 0
  GROUP BY qs.subject_id
)
SELECT 
  APPROX_QUANTILES(max_hr, 4)[OFFSET(3)] - APPROX_QUANTILES(max_hr, 4)[OFFSET(1)] AS iqr_max_heart_rate
FROM max_hr_per_patient
WHERE max_hr IS NOT NULL;