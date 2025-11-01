WITH spo2_events AS (
  SELECT
    ce.subject_id,
    ce.charttime,
    ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE LOWER(di.label) = 'spo2'
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 0 AND 100
),
first_spo2 AS (
  SELECT
    p.subject_id,
    s.valuenum AS first_spo2
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN (
    SELECT
      se.subject_id,
      se.valuenum,
      ROW_NUMBER() OVER (PARTITION BY se.subject_id ORDER BY se.charttime ASC) AS rn
    FROM spo2_events se
  ) s
    ON p.subject_id = s.subject_id
  WHERE s.rn = 1
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 62 AND 72
)
SELECT
  quantiles[OFFSET(3)] - quantiles[OFFSET(1)] AS iqr_first_spo2
FROM (
  SELECT APPROX_QUANTILES(first_spo2, 4) AS quantiles
  FROM first_spo2
);