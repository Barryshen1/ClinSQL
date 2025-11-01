WITH qualifying_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 38 AND 48
),
eligible_stays AS (
  SELECT s.subject_id, s.stay_id, s.intime
  FROM qualifying_patients qp
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` s
    ON qp.subject_id = s.subject_id
)
SELECT MAX(ce.valuenum) AS max_respiratory_rate
FROM eligible_stays es
INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON es.stay_id = ce.stay_id
INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
  ON ce.itemid = di.itemid
WHERE di.label = 'Respiratory Rate'
  AND ce.valuenum IS NOT NULL
  AND ce.charttime >= es.intime
  AND ce.charttime <= DATETIME_ADD(es.intime, INTERVAL 24 HOUR);