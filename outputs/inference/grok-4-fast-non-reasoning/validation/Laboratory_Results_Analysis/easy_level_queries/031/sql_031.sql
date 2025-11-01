WITH potassium_itemids AS (
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%potassium%'
    AND category = 'Chemistry'
),
eligible_patients AS (
  SELECT DISTINCT p.subject_id, i.hadm_id, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON p.subject_id = i.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.subject_id = a.subject_id AND i.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND a.dischtime IS NOT NULL
)
SELECT
  PERCENTILE_CONT(le.valuenum, 0.75) OVER() AS p75_serum_potassium
FROM eligible_patients ep
INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
  ON ep.subject_id = le.subject_id AND ep.hadm_id = le.hadm_id
INNER JOIN potassium_itemids ki
  ON le.itemid = ki.itemid
WHERE le.valuenum IS NOT NULL
  AND le.valuenum > 0
  AND DATE(le.charttime) = DATE(ep.dischtime);