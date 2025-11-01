WITH patient_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN i.stay_id IS NOT NULL THEN 'ICU'
      ELSE 'Non-ICU'
    END AS icu_status
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  WHERE p.gender = 'M'
    AND (EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age)) BETWEEN 77 AND 87
    AND a.dischtime IS NOT NULL
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 8
),
asthma_exacerbation AS (
  SELECT DISTINCT
    di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%asthma%exacerba%'
     OR LOWER(d.long_title) LIKE '%status asthmaticus%'
),
imaging_events AS (
  SELECT
    h.hadm_id,
    COUNT(*) AS imaging_count
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
    ON h.hcpcs_cd = d.code
  WHERE (LOWER(d.short_description) LIKE '%ct%'
         OR LOWER(d.short_description) LIKE '%mri%')
  GROUP BY h.hadm_id
),
cohort AS (
  SELECT
    pa.hadm_id,
    pa.los_days,
    pa.icu_status,
    COALESCE(ie.imaging_count, 0) AS imaging_count
  FROM patient_admissions pa
  INNER JOIN asthma_exacerbation ae
    ON pa.hadm_id = ae.hadm_id
  LEFT JOIN imaging_events ie
    ON pa.hadm_id = ie.hadm_id
),
stratified AS (
  SELECT
    icu_status,
    CASE
      WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN los_days BETWEEN 5 AND 8 THEN '5-8 days'
    END AS los_group,
    imaging_count
  FROM cohort
  WHERE los_days BETWEEN 1 AND 8
)
SELECT
  icu_status,
  los_group,
  AVG(imaging_count) AS mean_imaging_per_admission,
  MIN(imaging_count) AS min_imaging_per_admission,
  MAX(imaging_count) AS max_imaging_per_admission
FROM stratified
GROUP BY icu_status, los_group
ORDER BY icu_status, los_group;