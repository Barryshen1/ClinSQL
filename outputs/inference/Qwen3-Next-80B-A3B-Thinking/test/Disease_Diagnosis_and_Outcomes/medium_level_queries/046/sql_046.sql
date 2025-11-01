WITH patients_cohort AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 72 AND 82
),
hf_admissions AS (
  SELECT a.hadm_id, a.subject_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN patients_cohort pc ON a.subject_id = pc.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE di.long_title LIKE '%heart failure%' OR di.long_title LIKE '%congestive heart failure%'
  GROUP BY a.hadm_id, a.subject_id, a.admittime, a.dischtime, a.hospital_expire_flag
),
comorbidity_counts AS (
  SELECT d.hadm_id, COUNT(*) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE di.long_title NOT LIKE '%heart failure%' AND di.long_title NOT LIKE '%congestive heart failure%'
  GROUP BY d.hadm_id
),
icu_status AS (
  SELECT
    ha.hadm_id,
    ha.subject_id,
    ha.admittime,
    ha.dischtime,
    ha.hospital_expire_flag,
    CASE WHEN i.stay_id IS NOT NULL THEN 'ICU' ELSE 'Non-ICU' END AS icu_group,
    COALESCE(cc.comorbidity_count, 0) AS comorbidity_count
  FROM hf_admissions ha
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON ha.hadm_id = i.hadm_id
  LEFT JOIN comorbidity_counts cc ON ha.hadm_id = cc.hadm_id
)
SELECT
  icu_group,
  SUM(hospital_expire_flag) / COUNT(*) AS in_hospital_mortality,
  APPROX_QUANTILES(DATETIME_DIFF(dischtime, admittime, DAY), 2)[OFFSET(1)] AS median_los,
  AVG(comorbidity_count) AS avg_comorbidity_count
FROM icu_status
GROUP BY icu_group;