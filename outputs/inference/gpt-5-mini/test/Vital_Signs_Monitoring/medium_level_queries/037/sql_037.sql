SELECT
  COUNT(1) AS gcs_count,
  APPROX_QUANTILES(ce.valuenum, 2)[OFFSET(1)] AS median_gcs
FROM `physionet-data.mimiciv_3_1_icu.icustays` s
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON s.subject_id = p.subject_id
-- GCS total chart events on ICU day 2 or later
JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON s.subject_id = ce.subject_id
  AND s.hadm_id = ce.hadm_id
  AND s.stay_id = ce.stay_id
JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
  ON ce.itemid = di.itemid
WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 88 AND 98
  AND ce.charttime IS NOT NULL
  AND ce.valuenum IS NOT NULL
  -- GCS / Glasgow Total label heuristics
  AND (
    LOWER(di.label) LIKE '%gcs total%'
    OR (LOWER(di.label) LIKE '%glasgow%' AND LOWER(di.label) LIKE '%total%')
    OR LOWER(di.label) LIKE '%gcs score%'
    OR LOWER(di.label) LIKE '%glasgow coma scale%'
  )
  -- ICU day 2 or later: difference in days from ICU intime >= 1
  AND TIMESTAMP_DIFF(ce.charttime, s.intime, DAY) >= 1
  -- Ensure this ICU stay had at least one HFNC charted during the stay
  AND EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ch
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` di2
      ON ch.itemid = di2.itemid
    WHERE ch.subject_id = s.subject_id
      AND ch.hadm_id = s.hadm_id
      AND ch.stay_id = s.stay_id
      AND ch.charttime BETWEEN s.intime AND s.outtime
      AND (
        LOWER(di2.label) LIKE '%high flow%'
        OR LOWER(di2.label) LIKE '%high-flow%'
        OR LOWER(di2.label) LIKE '%highflow%'
        OR LOWER(di2.label) LIKE '%high flow nasal%'
        OR LOWER(di2.label) LIKE '%high-flow nasal%'
        OR LOWER(di2.label) LIKE '%high flow nasal cannula%'
        OR LOWER(di2.label) LIKE '%optiflow%'
        OR LOWER(di2.label) LIKE '%hfno%'
        OR LOWER(di2.label) LIKE '%hfnc%'
      )
  );