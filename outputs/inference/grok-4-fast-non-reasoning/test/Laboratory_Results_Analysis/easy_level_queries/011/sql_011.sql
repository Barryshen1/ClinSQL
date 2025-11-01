WITH filtered_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age = 56
),
potassium_measurements AS (
  SELECT ce.subject_id, ce.hadm_id, ce.stay_id, ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN filtered_patients fp ON ce.subject_id = fp.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu 
    ON ce.subject_id = icu.subject_id 
    AND ce.hadm_id = icu.hadm_id 
    AND ce.stay_id = icu.stay_id
    AND ce.charttime BETWEEN icu.intime AND icu.outtime
  WHERE ce.itemid IN (614, 227464)  -- Serum potassium (S) in mEq/L
    AND ce.valuenum IS NOT NULL 
    AND ce.valuenum > 0
)
SELECT STDDEV(peak_k) AS stddev_peak_serum_potassium_meq_l
FROM (
  SELECT stay_id, MAX(valuenum) AS peak_k
  FROM potassium_measurements
  GROUP BY stay_id
);