WITH hep_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id
   AND a.hadm_id    = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code    = icd.icd_code
   AND d.icd_version = icd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 75 AND 85
    AND LOWER(icd.long_title) LIKE '%hepatic failure%'
),
general_cohort AS (
  -- All inpatients age 75-85 regardless of diagnosis or gender
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.anchor_age BETWEEN 75 AND 85
),
icustay_window AS (
  -- Restrict ICU stay to first 48h of hospital admission
  SELECT
    hc.subject_id,
    hc.hadm_id,
    icu.stay_id,
    hc.admittime,
    hc.dischtime,
    hc.hospital_expire_flag,
    hc.admittime + INTERVAL 48 HOUR AS window_end
  FROM hep_cohort hc
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON hc.subject_id = icu.subject_id
   AND hc.hadm_id    = icu.hadm_id
  WHERE icu.intime < hc.admittime + INTERVAL 48 HOUR
    AND icu.outtime > hc.admittime
),
hep_hr AS (
  -- Max heart rate (itemid=211) in first 48h for each patient
  SELECT
    iw.subject_id,
    iw.hadm_id,
    MAX(ce.valuenum) AS max_hr
  FROM icustay_window iw
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON iw.stay_id = ce.stay_id
   AND ce.itemid = 211
   AND ce.charttime BETWEEN iw.admittime AND iw.window_end
  GROUP BY iw.subject_id, iw.hadm_id
),
hep_lactate AS (
  -- Count of lactate labs in first 48h per patient
  SELECT
    hc.subject_id,
    hc.hadm_id,
    COUNT(*) AS lactate_count
  FROM hep_cohort hc
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON hc.subject_id = le.subject_id
   AND hc.hadm_id    = le.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di
    ON le.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%lactate%'
    AND le.charttime BETWEEN hc.admittime
                       AND hc.admittime + INTERVAL 48 HOUR
  GROUP BY hc.subject_id, hc.hadm_id
),
gen_lactate AS (
  -- Count of lactate labs in first 48h per patient in the general cohort
  SELECT
    gc.subject_id,
    gc.hadm_id,
    COUNT(*) AS lactate_count
  FROM general_cohort gc
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON gc.subject_id = le.subject_id
   AND gc.hadm_id    = le.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di
    ON le.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%lactate%'
    AND le.charttime BETWEEN gc.admittime
                       AND gc.admittime + INTERVAL 48 HOUR
  GROUP BY gc.subject_id, gc.hadm_id
)
SELECT
  -- Instability metric
  MAX(hh.max_hr)                            AS max_instability_hr,
  -- Mortality rate
  SAFE_DIVIDE(
    SUM(icw.hospital_expire_flag),
    COUNT(DISTINCT icw.hadm_id)
  )                                          AS mortality_rate,
  -- Average LOS in days
  AVG(TIMESTAMP_DIFF(icw.dischtime, icw.admittime, DAY)) AS avg_los_days,
  -- Average lactate labs per patient in cohort
  AVG(hep_lactate.lactate_count)            AS avg_lactate_cohort,
  -- Average lactate labs per patient in general inpatient comparator
  (SELECT AVG(lactate_count) FROM gen_lactate) AS avg_lactate_general
FROM icustay_window icw
LEFT JOIN hep_hr hh
  ON icw.subject_id = hh.subject_id
 AND icw.hadm_id    = hh.hadm_id
LEFT JOIN hep_lactate
  ON icw.subject_id = hep_lactate.subject_id
 AND icw.hadm_id    = hep_lactate.hadm_id;