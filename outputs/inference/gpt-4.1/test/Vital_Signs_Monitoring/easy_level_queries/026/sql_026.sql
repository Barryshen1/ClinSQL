WITH resp_rate_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%respiratory rate%'
),

cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    pat.anchor_age,
    pat.gender,
    icu.intime,
    icu.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 39 AND 49
)

SELECT
  c.subject_id,
  c.hadm_id,
  c.stay_id,
  c.anchor_age,
  c.gender,
  MIN(ce.valuenum) AS min_respiratory_rate_24hr
FROM cohort c
JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON c.subject_id = ce.subject_id
  AND c.stay_id = ce.stay_id
  AND ce.charttime >= c.intime
  AND ce.charttime < DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
WHERE ce.valuenum IS NOT NULL
  AND ce.itemid IN (SELECT itemid FROM resp_rate_items)
GROUP BY c.subject_id, c.hadm_id, c.stay_id, c.anchor_age, c.gender
ORDER BY min_respiratory_rate_24hr;