WITH hr_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%heart rate%'
),

-- Compute per-stay average heart rate for ICU stays (within stay period)
per_stay AS (
  SELECT
    s.stay_id,
    s.hadm_id,
    s.subject_id,
    AVG(e.valuenum) AS avg_hr
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS e
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS s
    ON s.hadm_id = e.hadm_id
   AND s.stay_id = e.stay_id
  JOIN hr_items AS hi
    ON e.itemid = hi.itemid
  WHERE
    e.charttime BETWEEN s.intime AND s.outtime
    AND e.valuenum IS NOT NULL
  GROUP BY s.stay_id, s.hadm_id, s.subject_id
)

SELECT
  SAFE_DIVIDE(100.0 * COUNTIF(avg_hr <= 110), COUNT(*)) AS percentile_110
FROM per_stay ps
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON p.subject_id = ps.subject_id
WHERE
  p.gender = 'Female'
  AND p.anchor_age BETWEEN 80 AND 90;