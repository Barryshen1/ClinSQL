WITH filtered_stays AS (
  SELECT 
    i.stay_id,
    i.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
),
bp_measurements AS (
  SELECT
    f.stay_id,
    c.valuenum
  FROM filtered_stays f
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON f.stay_id = c.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` d
    ON c.itemid = d.itemid
  WHERE d.label LIKE '%Systolic%'
    AND c.charttime BETWEEN f.intime AND f.intime + INTERVAL 48 HOUR
),
avg_bp AS (
  SELECT
    stay_id,
    AVG(valuenum) AS avg_sbp
  FROM bp_measurements
  GROUP BY stay_id
)
SELECT
  SUM(CASE WHEN avg_sbp <= 130 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS percentile
FROM avg_bp;