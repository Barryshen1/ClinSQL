WITH patient_filter AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 57 AND 67
),
echo_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE label LIKE '%echocardiogram%' OR label LIKE '%echocardiography%'
),
echo_procedures AS (
  SELECT pe.subject_id, COUNT(DISTINCT pe.itemid) as num_procedures
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN echo_itemids ei ON pe.itemid = ei.itemid
  WHERE pe.subject_id IN (SELECT subject_id FROM patient_filter)
  GROUP BY pe.subject_id
)
SELECT APPROX_QUANTILES(num_procedures, 100)[OFFSET(75)] AS percentile_75th
FROM echo_procedures;