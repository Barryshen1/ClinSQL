WITH troponin_events AS (
  SELECT
    l.hadm_id,
    l.subject_id,
    l.charttime,
    l.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS d
    ON l.itemid = d.itemid
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON l.hadm_id = a.hadm_id AND l.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE (
        LOWER(d.label) LIKE '%troponin-t%' OR
        LOWER(d.label) LIKE '%troponin t%'
      )
    AND l.valuenum IS NOT NULL
    AND p.gender = 'Male'
    AND p.anchor_age BETWEEN 54 AND 64
),
first_troponin AS (
  SELECT hadm_id, valuenum
  FROM (
    SELECT hadm_id, valuenum, charttime,
           ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime ASC) AS rn
    FROM troponin_events
  )
  WHERE rn = 1 AND valuenum > 0.01
),
summary AS (
  SELECT
    COUNT(*) AS n,
    AVG(valuenum) AS mean,
    STDDEV_SAMP(valuenum) AS sd,
    MIN(valuenum) AS min,
    MAX(valuenum) AS max
  FROM first_troponin
)
SELECT
  s.n,
  s.mean,
  s.sd,
  s.min,
  s.max,
  (SELECT PERCENTILE_CONT(valuenum, 0.25) OVER () FROM first_troponin LIMIT 1) AS q1,
  (SELECT PERCENTILE_CONT(valuenum, 0.5) OVER () FROM first_troponin LIMIT 1) AS median,
  (SELECT PERCENTILE_CONT(valuenum, 0.75) OVER () FROM first_troponin LIMIT 1) AS q3
FROM summary s;