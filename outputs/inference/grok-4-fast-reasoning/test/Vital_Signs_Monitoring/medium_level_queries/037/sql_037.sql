WITH eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 88 AND 98
),
hfnc_stays AS (
  SELECT DISTINCT ce.subject_id, ce.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE (LOWER(di.label) LIKE '%high flow%' OR LOWER(di.label) LIKE '%hfnc%')
    AND ce.stay_id IS NOT NULL
    AND ce.subject_id IN (SELECT subject_id FROM eligible_patients)
),
eligible_stays AS (
  SELECT i.subject_id, i.stay_id, i.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN eligible_patients ep
    ON i.subject_id = ep.subject_id
  INNER JOIN hfnc_stays hs
    ON i.stay_id = hs.stay_id
),
gcs_components AS (
  SELECT ce.subject_id, ce.stay_id, ce.charttime, ce.itemid, ce.valuenum, es.intime
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN eligible_stays es
    ON ce.subject_id = es.subject_id
    AND ce.stay_id = es.stay_id
  WHERE ce.itemid IN (220739, 223900, 223901)
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= TIMESTAMP_ADD(es.intime, INTERVAL 1 DAY)
),
gcs_totals AS (
  SELECT
    subject_id,
    stay_id,
    charttime,
    SUM(valuenum) AS gcs_total
  FROM gcs_components
  GROUP BY subject_id, stay_id, charttime
  HAVING COUNT(DISTINCT itemid) = 3
)
SELECT
  COUNT(*) AS num_gcs_records,
  IF(COUNT(*) > 0, APPROX_QUANTILES(gcs_total, 2)[OFFSET(1)], NULL) AS median_gcs
FROM gcs_totals;