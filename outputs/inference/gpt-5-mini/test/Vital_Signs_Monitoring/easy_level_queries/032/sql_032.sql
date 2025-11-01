WITH
-- ICU stays for female patients aged 38-48
icu_females AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    p.anchor_age,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  USING(subject_id)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
),

-- Identify candidate d_items corresponding to respiratory rate
rr_itemids AS (
  SELECT DISTINCT itemid
  FROM
    `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE
    -- look for common phrasing of respiratory rate in the item label / abbreviation
    (
      REGEXP_CONTAINS(LOWER(label), r'respirat.*rate')
      OR REGEXP_CONTAINS(LOWER(label), r'\bresp rate\b')
      OR REGEXP_CONTAINS(LOWER(abbreviation), r'\brr\b')
    )
),

-- Pull RR chart events that fall within first 24 hours of the icu stay
rr_events_first24 AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    ce.charttime,
    ce.valuenum
  FROM
    icu_females f
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.subject_id = f.subject_id
    AND ce.stay_id = f.stay_id
  JOIN
    rr_itemids r
    ON ce.itemid = r.itemid
  WHERE
    ce.valuenum IS NOT NULL
    AND ce.charttime >= f.intime
    AND ce.charttime <= TIMESTAMP_ADD(f.intime, INTERVAL 24 HOUR)
),

-- Compute max RR per ICU stay in the first 24 hours
max_rr_per_stay AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    f.intime,
    f.anchor_age,
    MAX(e.valuenum) AS max_rr_first24
  FROM
    icu_females f
  LEFT JOIN
    rr_events_first24 e
  USING(subject_id, hadm_id, stay_id)
  GROUP BY
    f.subject_id, f.hadm_id, f.stay_id, f.intime, f.anchor_age
)

-- Final: show stays for 43-year-old female(s) (within the 38-48 cohort) and their max RR in first 24h
SELECT
  subject_id,
  hadm_id,
  stay_id,
  anchor_age,
  intime,
  max_rr_first24
FROM
  max_rr_per_stay
WHERE
  anchor_age = 43
ORDER BY
  subject_id,
  stay_id;