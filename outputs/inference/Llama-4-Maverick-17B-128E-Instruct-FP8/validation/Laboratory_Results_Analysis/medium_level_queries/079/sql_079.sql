WITH patients AS (
  SELECT p.subject_id, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 82 AND 92
),
troponin_t AS (
  SELECT l.hadm_id, l.valuenum, ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) as troponin_seq
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl ON l.itemid = dl.itemid
  WHERE dl.itemid = 50821 AND l.valuenum > 0.01
)
SELECT 
  APPROX_QUANTILES(t.valuenum, 100)[OFFSET(25)] AS p25,
  APPROX_QUANTILES(t.valuenum, 100)[OFFSET(50)] AS p50,
  APPROX_QUANTILES(t.valuenum, 100)[OFFSET(75)] AS p75,
  MIN(t.valuenum) AS min_val,
  MAX(t.valuenum) AS max_val
FROM patients p
JOIN troponin_t t ON p.hadm_id = t.hadm_id
WHERE t.troponin_seq = 1;