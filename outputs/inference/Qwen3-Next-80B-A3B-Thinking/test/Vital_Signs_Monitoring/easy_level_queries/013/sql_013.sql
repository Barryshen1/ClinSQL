SELECT MIN(ce.valuenum) AS min_heart_rate
FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
  ON ce.hadm_id = adm.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON ce.subject_id = p.subject_id
JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
  ON ce.itemid = di.itemid
WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 44 AND 54
  AND di.label = 'Heart Rate'
  AND ce.charttime >= adm.admittime
  AND ce.charttime <= adm.admittime + INTERVAL '24' HOUR
  AND ce.valuenum IS NOT NULL;