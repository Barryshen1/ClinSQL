SELECT MIN(ce.valuenum) AS min_heart_rate
FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ic
  ON ce.subject_id = ic.subject_id
  AND ce.hadm_id = ic.hadm_id
  AND ce.stay_id = ic.stay_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
  ON ic.subject_id = adm.subject_id
  AND ic.hadm_id = adm.hadm_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON adm.subject_id = p.subject_id
WHERE ce.itemid = 220045
  AND ce.valuenum IS NOT NULL
  AND p.gender = 'F'
  AND (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year + p.anchor_age) BETWEEN 44 AND 54
  AND ce.charttime >= ic.intime
  AND ce.charttime < DATETIME_ADD(ic.intime, INTERVAL 24 HOUR);