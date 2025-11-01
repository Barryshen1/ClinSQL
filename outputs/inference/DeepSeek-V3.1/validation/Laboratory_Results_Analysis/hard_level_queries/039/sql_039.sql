WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime, 
    adm.hospital_expire_flag,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los,
    pat.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddiag
    ON diag.icd_code = ddiag.icd_code AND diag.icd_version = ddiag.icd_version
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 60 AND 70
    AND diag.seq_num = 1
    AND ddiag.long_title LIKE '%pneumonia%'
),
-- Get abnormal lab count in first 72 hours for each cohort patient
lab_abnormalities AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    COUNT(DISTINCT le.itemid) AS abnormal_lab_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON c.hadm_id = le.hadm_id
    AND le.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
    AND (
      le.flag IS NOT NULL 
      OR (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper)
    )
  GROUP BY c.subject_id, c.hadm_id
),
-- Count ICU transfers for each cohort patient
cohort_icu_transfers AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    COUNT(DISTINCT t.transfer_id) AS icu_transfer_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.transfers` t
    ON c.hadm_id = t.hadm_id
    AND t.eventtype = 'transfer'
    AND t.careunit LIKE '%ICU%'
  GROUP BY c.subject_id, c.hadm_id
),
-- For "all inpatients": all adult admissions
all_inpatients AS (
  SELECT 
    adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.anchor_age >= 18
),
-- Count ICU transfers for all inpatients
all_inpatients_icu_transfers AS (
  SELECT
    a.hadm_id,
    COUNT(DISTINCT t.transfer_id) AS icu_transfer_count
  FROM all_inpatients a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.transfers` t
    ON a.hadm_id = t.hadm_id
    AND t.eventtype = 'transfer'
    AND t.careunit LIKE '%ICU%'
  GROUP BY a.hadm_id
),
-- Calculate 75th percentile of abnormal lab count for cohort
cohort_percentile AS (
  SELECT
    PERCENTILE_CONT(abnormal_lab_count, 0.75) OVER() AS percentile_75_abnormal_labs
  FROM lab_abnormalities
  LIMIT 1
)
SELECT
  -- 75th percentile of abnormal lab count
  (SELECT percentile_75_abnormal_labs FROM cohort_percentile) AS percentile_75_abnormal_labs,
  -- Mean ICU transfer count for cohort
  AVG(cit.icu_transfer_count) AS mean_icu_transfers_cohort,
  -- Mean ICU transfer count for all inpatients
  (SELECT AVG(icu_transfer_count) FROM all_inpatients_icu_transfers) AS mean_icu_transfers_all,
  -- Cohort LOS and mortality
  AVG(c.los) AS avg_los,
  SUM(c.hospital_expire_flag) AS mortality_count,
  COUNT(*) AS cohort_count,
  SUM(c.hospital_expire_flag) / COUNT(*) AS mortality_rate
FROM cohort c
INNER JOIN lab_abnormalities la ON c.hadm_id = la.hadm_id
INNER JOIN cohort_icu_transfers cit ON c.hadm_id = cit.hadm_id;