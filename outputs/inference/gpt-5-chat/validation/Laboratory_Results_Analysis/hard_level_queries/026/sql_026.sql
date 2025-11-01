WITH hepatic_cohort AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    icu.stay_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    icu.intime,
    icu.outtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi
    ON di.icd_code = ddi.icd_code AND di.icd_version = ddi.icd_version
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON a.subject_id = icu.subject_id AND a.hadm_id = icu.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 75 AND 85
    AND LOWER(ddi.long_title) LIKE '%hepatic failure%'
),
instability_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%instability%'
),
instability_scores AS (
  SELECT
    hc.subject_id,
    MAX(ce.valuenum) AS max_instability_48h
  FROM hepatic_cohort hc
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON hc.subject_id = ce.subject_id
    AND hc.stay_id = ce.stay_id
  WHERE ce.itemid IN (SELECT itemid FROM instability_items)
    AND TIMESTAMP_DIFF(ce.charttime, hc.intime, MINUTE) BETWEEN 0 AND 48*60
    AND ce.valuenum IS NOT NULL
  GROUP BY hc.subject_id
),
critical_labs_cohort AS (
  SELECT
    COUNTIF(LOWER(le.flag) IN ('abnormal','critical')) AS critical_lab_count,
    COUNT(*) AS total_lab_count
  FROM hepatic_cohort hc
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON hc.subject_id = le.subject_id AND hc.hadm_id = le.hadm_id
  WHERE TIMESTAMP_DIFF(le.charttime, hc.intime, MINUTE) BETWEEN 0 AND 48*60
),
critical_labs_all AS (
  SELECT
    COUNTIF(LOWER(le.flag) IN ('abnormal','critical')) AS critical_lab_count,
    COUNT(*) AS total_lab_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON a.subject_id = icu.subject_id AND a.hadm_id = icu.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON a.subject_id = le.subject_id AND a.hadm_id = le.hadm_id
  WHERE TIMESTAMP_DIFF(le.charttime, icu.intime, MINUTE) BETWEEN 0 AND 48*60
)
SELECT
  MAX(iscore.max_instability_48h) AS cohort_max_instability_score_48h,
  AVG(TIMESTAMP_DIFF(hc.dischtime, hc.admittime, DAY)) AS avg_hosp_los_days,
  AVG(hc.hospital_expire_flag) AS mortality_rate, -- proportion since flag is 1 for death
  MAX(clc.critical_lab_count) AS cohort_critical_lab_count,
  MAX(clc.total_lab_count) AS cohort_total_labs,
  MAX(SAFE_DIVIDE(clc.critical_lab_count, clc.total_lab_count)) AS cohort_critical_lab_proportion,
  MAX(cla.critical_lab_count) AS all_critical_lab_count,
  MAX(cla.total_lab_count) AS all_total_labs,
  MAX(SAFE_DIVIDE(cla.critical_lab_count, cla.total_lab_count)) AS all_critical_lab_proportion
FROM hepatic_cohort hc
LEFT JOIN instability_scores iscore
  ON hc.subject_id = iscore.subject_id
CROSS JOIN critical_labs_cohort clc
CROSS JOIN critical_labs_all cla;