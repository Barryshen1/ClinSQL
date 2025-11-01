WITH admissions_filtered AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age - (p.anchor_year - EXTRACT(YEAR FROM a.admittime))) BETWEEN 64 AND 74
),
aspirin AS (
  SELECT 
    p.hadm_id,
    GREATEST(p.starttime, a.admittime) AS start_time,
    LEAST(COALESCE(p.stoptime, a.dischtime), a.dischtime) AS end_time
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN admissions_filtered a
    ON p.hadm_id = a.hadm_id
  WHERE LOWER(p.drug) LIKE '%aspirin%'
),
p2y12 AS (
  SELECT 
    p.hadm_id,
    GREATEST(p.starttime, a.admittime) AS start_time,
    LEAST(COALESCE(p.stoptime, a.dischtime), a.dischtime) AS end_time
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN admissions_filtered a
    ON p.hadm_id = a.hadm_id
  WHERE REGEXP_CONTAINS(LOWER(p.drug), r'clopidogrel|prasugrel|ticagrelor')
),
events AS (
  SELECT 
    hadm_id,
    start_time AS time,
    1 AS aspirin_delta,
    0 AS p2y12_delta
  FROM aspirin
  UNION ALL
  SELECT 
    hadm_id,
    end_time,
    -1,
    0
  FROM aspirin
  UNION ALL
  SELECT 
    hadm_id,
    start_time,
    0,
    1
  FROM p2y12
  UNION ALL
  SELECT 
    hadm_id,
    end_time,
    0,
    -1
  FROM p2y12
),
timeline AS (
  SELECT 
    hadm_id,
    time,
    SUM(aspirin_delta) OVER w AS aspirin_count,
    SUM(p2y12_delta) OVER w AS p2y12_count
  FROM events
  WINDOW w AS (PARTITION BY hadm_id ORDER BY time)
),
timeline_with_lead AS (
  SELECT 
    hadm_id,
    time,
    aspirin_count,
    p2y12_count,
    LEAD(time) OVER w AS next_time
  FROM timeline
  WINDOW w AS (PARTITION BY hadm_id ORDER BY time)
),
dual_therapy_seconds AS (
  SELECT 
    hadm_id,
    SUM(TIMESTAMP_DIFF(next_time, time, SECOND)) AS dual_therapy_seconds
  FROM timeline_with_lead
  WHERE aspirin_count > 0 
    AND p2y12_count > 0
    AND next_time IS NOT NULL
  GROUP BY hadm_id
  HAVING SUM(TIMESTAMP_DIFF(next_time, time, SECOND)) > 0
),
dual_therapy_days AS (
  SELECT 
    hadm_id,
    dts.dual_therapy_seconds / (24 * 60 * 60) AS duration_days
  FROM dual_therapy_seconds dts
),
ordered AS (
  SELECT 
    duration_days,
    ROW_NUMBER() OVER (ORDER BY duration_days) AS rn,
    COUNT(*) OVER () AS cnt
  FROM dual_therapy_days
)
SELECT 
  AVG(duration_days) AS median_duration_days
FROM ordered
WHERE rn IN (FLOOR((cnt + 1) / 2), CEIL((cnt + 1) / 2));