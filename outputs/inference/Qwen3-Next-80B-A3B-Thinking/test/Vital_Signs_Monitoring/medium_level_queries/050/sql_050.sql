WITH relevant_stays AS (
  SELECT
    i.stay_id,
    i.intime,
    p.anchor_age,
    p.anchor_year,
    p.gender
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (EXTRACT(YEAR FROM i.intime) - p.anchor_year) BETWEEN 67 AND 77
),
hr_data AS (
  SELECT
    rs.stay_id,
    AVG(ce.valuenum) AS avg_hr
  FROM relevant_stays rs
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON rs.stay_id = ce.stay_id
    AND ce.itemid = 211
    AND ce.charttime BETWEEN rs.intime AND rs.intime + INTERVAL '24' HOUR
  GROUP BY rs.stay_id
)
SELECT
  (COUNTIF(avg_hr <= 110) * 100.0) / NULLIF(COUNT(*), 0) AS percentile
FROM hr_data
WHERE avg_hr IS NOT NULL;