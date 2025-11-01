WITH serum_potassium AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    l.valuenum,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON a.subject_id = icu.subject_id
   AND a.hadm_id = icu.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON a.subject_id = l.subject_id
   AND a.hadm_id = l.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON l.itemid = dl.itemid
  WHERE p.gender = 'M'
    AND dl.label = 'Potassium'
    AND dl.category = 'Chemistry'
    AND l.valuenum IS NOT NULL
    AND DATE(l.charttime) = DATE(a.dischtime)
)
SELECT
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS potassium_75th_percentile
FROM serum_potassium;