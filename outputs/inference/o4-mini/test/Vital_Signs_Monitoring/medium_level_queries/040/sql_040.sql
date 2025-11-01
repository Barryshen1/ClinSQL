WITH
-- 1. Female patients aged 81–91
eligible_patients AS (
  SELECT
    p.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 81 AND 91
),

-- 2. ICU stays for those patients
eligible_icustays AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN
    eligible_patients ep
  USING(subject_id)
),

-- 3. Stays with high-flow nasal cannula recorded
hfnc_stays AS (
  SELECT DISTINCT
    pe.stay_id
  FROM
    `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
  ON
    pe.itemid = di.itemid
  WHERE
    LOWER(di.label) LIKE '%high flow nasal cannula%'
),

-- 4. SBP measurements during eligible stays
sbp_events AS (
  SELECT
    ce.stay_id,
    ce.valuenum
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
  ON
    ce.itemid = di.itemid
  JOIN
    eligible_icustays icu
  ON
    ce.stay_id = icu.stay_id
    AND ce.charttime BETWEEN icu.intime AND icu.outtime
  WHERE
    ce.valuenum IS NOT NULL
    AND LOWER(di.label) LIKE '%systolic%'
    AND LOWER(di.label) LIKE '%bp%'
),

-- 5. Compute mean SBP per stay, but only for HFNC stays
mean_sbp_per_stay AS (
  SELECT
    se.stay_id,
    AVG(se.valuenum) AS mean_sbp
  FROM
    sbp_events se
  JOIN
    hfnc_stays h
  ON
    se.stay_id = h.stay_id
  GROUP BY
    se.stay_id
)

-- 6. Find the minimum of the per-stay means
SELECT
  MIN(mean_sbp) AS min_per_stay_mean_sbp
FROM
  mean_sbp_per_stay;