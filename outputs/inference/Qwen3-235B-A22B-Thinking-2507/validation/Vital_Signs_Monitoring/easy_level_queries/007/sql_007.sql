WITH population AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 73 AND 83
),
first_icu_stay AS (
  SELECT 
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime
  FROM (
    SELECT 
      *,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) AS stay_rank
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) i
  INNER JOIN population p
    ON i.subject_id = p.subject_id AND i.hadm_id = p.hadm_id
  WHERE i.stay_rank = 1
),
first_resp_rate AS (
  SELECT 
    c.stay_id,
    c.valuenum AS resp_rate,
    ROW_NUMBER() OVER (PARTITION BY c.stay_id ORDER BY c.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  INNER JOIN first_icu_stay i
    ON c.stay_id = i.stay_id
  WHERE c.itemid = 220210  -- Confirmed: Respiratory Rate in d_items
    AND c.charttime >= i.intime
    AND c.charttime <= i.outtime
    AND c.valuenum IS NOT NULL
)
SELECT 
  STDDEV(resp_rate) AS resp_rate_stddev
FROM first_resp_rate
WHERE rn = 1;