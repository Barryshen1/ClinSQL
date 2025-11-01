WITH qualifying_stays AS (
  SELECT DISTINCT i.stay_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON p.subject_id = i.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age >= 51
    AND p.anchor_age <= 61
),
rr_events AS (
  SELECT 
    c.stay_id,
    c.charttime,
    c.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON c.itemid = di.itemid
  JOIN qualifying_stays qs
    ON c.stay_id = qs.stay_id
  WHERE LOWER(di.label) LIKE '%respiratory rate%'
    AND c.valuenum IS NOT NULL
),
ranked_rr AS (
  SELECT 
    stay_id,
    valuenum AS first_rr,
    ROW_NUMBER() OVER (
      PARTITION BY stay_id 
      ORDER BY charttime ASC
    ) AS rn
  FROM rr_events
)
SELECT STDDEV_SAMP(first_rr) AS sd_first_respiratory_rate
FROM ranked_rr
WHERE rn = 1;