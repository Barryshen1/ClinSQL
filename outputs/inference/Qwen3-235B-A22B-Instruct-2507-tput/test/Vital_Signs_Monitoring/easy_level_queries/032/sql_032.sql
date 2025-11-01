SELECT MAX(ce.valuenum) AS max_respiratory_rate
FROM `physionet-data.mimiciv_3_1_icu`.icustays icu
JOIN `physionet-data.mimiciv_3_1_hosp`.admissions adm
  ON icu.hadm_id = adm.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
  ON adm.subject_id = p.subject_id
JOIN `physionet-data.mimiciv_3_1_icu`.chartevents ce
  ON icu.stay_id = ce.stay_id
JOIN `physionet-data.mimiciv_3_1_icu`.d_items di
  ON ce.itemid = di.itemid
WHERE p.gender = 'F'
  -- Calculate age at ICU admission
  AND (p.anchor_age + EXTRACT(YEAR FROM icu.intime) - p.anchor_year) BETWEEN 38 AND 48
  AND LOWER(di.label) = 'respiratory rate'
  AND ce.charttime >= icu.intime
  AND ce.charttime < DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
  AND ce.valuenum IS NOT NULL;