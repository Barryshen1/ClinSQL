WITH eligible_admissions AS (
  SELECT 
    p.subject_id, 
    a.hadm_id,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
),
filtered_admissions AS (
  SELECT subject_id, hadm_id
  FROM eligible_admissions
  WHERE age_at_admission BETWEEN 59 AND 69
),
troponin_events AS (
  SELECT 
    fa.hadm_id,
    le.labevent_id,
    le.charttime,
    le.valuenum
  FROM filtered_admissions fa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON fa.subject_id = le.subject_id
    AND fa.hadm_id = le.hadm_id
  WHERE le.itemid = 51003  -- hs-TnT
    AND le.valuenum > 0.014
),
first_troponin_per_admission AS (
  SELECT 
    hadm_id,
    valuenum,
    ROW_NUMBER() OVER (
      PARTITION BY hadm_id 
      ORDER BY charttime, labevent_id
    ) AS rn
  FROM troponin_events
)
SELECT 
  MIN(valuenum) AS min_value,
  MAX(valuenum) AS max_value,
  APPROX_QUANTILES(valuenum, 100)[SAFE_OFFSET(25)] AS p25,
  APPROX_QUANTILES(valuenum, 100)[SAFE_OFFSET(50)] AS p50,
  APPROX_QUANTILES(valuenum, 100)[SAFE_OFFSET(75)] AS p75
FROM first_troponin_per_admission
WHERE rn = 1;