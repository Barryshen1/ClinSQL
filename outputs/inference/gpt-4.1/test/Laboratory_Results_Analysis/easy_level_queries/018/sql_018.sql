WITH female_icu_stays AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
),
ph_itemids AS (
  SELECT
    itemid
  FROM
    `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE
    LOWER(label) LIKE '%ph%'
    AND (
      LOWER(category) LIKE '%blood gas%'
      OR LOWER(label) LIKE '%arterial%'
      OR LOWER(label) LIKE '%abg%'
    )
),
ph_measurements AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    INNER JOIN ph_itemids
      ON ce.itemid = ph_itemids.itemid
  WHERE
    ce.valuenum IS NOT NULL
)
SELECT
  s.subject_id,
  s.hadm_id,
  s.stay_id,
  APPROX_QUANTILES(m.valuenum, 2)[OFFSET(1)] AS median_ph
FROM
  female_icu_stays s
  INNER JOIN ph_measurements m
    ON s.subject_id = m.subject_id
    AND s.hadm_id = m.hadm_id
    AND s.stay_id = m.stay_id
    AND m.charttime >= s.intime
    AND m.charttime < TIMESTAMP_ADD(s.intime, INTERVAL 6 HOUR)
GROUP BY
  s.subject_id, s.hadm_id, s.stay_id
HAVING
  median_ph IS NOT NULL
ORDER BY
  s.subject_id, s.hadm_id, s.stay_id;