WITH patient_stays AS (
  SELECT 
    i.subject_id, 
    i.stay_id, 
    i.hadm_id, 
    i.intime, 
    i.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'M' 
    AND p.anchor_age = 56
),
peak_k_per_stay AS (
  SELECT 
    ps.subject_id,
    ps.stay_id,
    MAX(le.valuenum) AS peak_k
  FROM patient_stays ps
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le 
    ON le.subject_id = ps.subject_id
    AND le.hadm_id = ps.hadm_id
    AND le.itemid = 50971
    AND le.valuenum IS NOT NULL
    AND le.valueuom = 'mEq/L'
    AND le.charttime >= ps.intime
    AND le.charttime <= ps.outtime
  GROUP BY ps.subject_id, ps.stay_id
)
SELECT 
  STDDEV_SAMP(peak_k) AS stddev_of_peak_serum_potassium_mEq_L
FROM peak_k_per_stay
WHERE peak_k IS NOT NULL;