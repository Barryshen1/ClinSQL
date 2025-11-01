WITH patients_filtered AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 37 AND 47
),
first_icu_admission AS (
  SELECT subject_id, hadm_id, stay_id, intime,
         ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS icu_admit_seq
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
first_spo2 AS (
  SELECT ce.subject_id, ce.valuenum,
         ROW_NUMBER() OVER (PARTITION BY ce.subject_id ORDER BY ce.charttime) AS spo2_seq
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN first_icu_admission fia ON ce.stay_id = fia.stay_id AND fia.icu_admit_seq = 1
  JOIN patients_filtered pf ON ce.subject_id = pf.subject_id
  WHERE ce.itemid = (SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items` WHERE label LIKE '%SpO2%' LIMIT 1)
  AND ce.charttime >= fia.intime
)
SELECT 
  APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] AS q1,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS q3
FROM first_spo2
WHERE spo2_seq = 1;