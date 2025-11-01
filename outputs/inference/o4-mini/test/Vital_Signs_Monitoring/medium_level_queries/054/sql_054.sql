WITH
-- 1. Define cohort: female patients age 87–97
cohort AS (
  SELECT
    p.subject_id,
    icu.stay_id,
    icu.intime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
      USING(subject_id)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 87 AND 97
),

-- 2. Identify SBP itemids
sbp_items AS (
  SELECT
    itemid
  FROM
    `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE
    LOWER(label) LIKE '%systolic%'
),

-- 3. Compute per-stay average SBP in first 24h
stay_avg_sbp AS (
  SELECT
    c.stay_id,
    AVG(ce.valuenum) AS avg_sbp
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
      ON ce.subject_id = c.subject_id
      AND ce.stay_id = c.stay_id
    JOIN sbp_items si
      ON ce.itemid = si.itemid
  WHERE
    ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN c.intime
                        AND TIMESTAMP_ADD(c.intime, INTERVAL 24 HOUR)
  GROUP BY
    c.stay_id
)

-- 4. Compute empirical percentile of 150 mmHg
SELECT
  150 AS target_sbp,
  100.0 * SUM(CASE WHEN avg_sbp <= 150 THEN 1 ELSE 0 END) / COUNT(*) AS percentile_rank
FROM
  stay_avg_sbp;