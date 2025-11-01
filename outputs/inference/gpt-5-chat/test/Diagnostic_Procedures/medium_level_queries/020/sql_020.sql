WITH tia_patients AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    p.gender,
    p.anchor_age,
    DATE_DIFF(DATE(adm.dischtime), DATE(adm.admittime), DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON adm.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 72 AND 82
    AND UPPER(dd.long_title) LIKE '%TRANSIENT ISCHEMIC%'
),
cohort AS (
  SELECT
    t.subject_id,
    t.hadm_id,
    CASE
      WHEN t.los_days BETWEEN 1 AND 3 THEN 'LOS_1_3'
      WHEN t.los_days BETWEEN 4 AND 7 THEN 'LOS_4_7'
      ELSE NULL
    END AS los_group
  FROM tia_patients t
  WHERE t.los_days BETWEEN 1 AND 7
),
icu_flags AS (
  SELECT DISTINCT
    hadm_id,
    1 AS icu_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
imaging_counts AS (
  SELECT
    proc.hadm_id,
    COUNT(*) AS imaging_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON proc.icd_code = dp.icd_code AND proc.icd_version = dp.icd_version
  WHERE REGEXP_CONTAINS(UPPER(dp.long_title), r'CT|MRI|ULTRASOUND|RADIOLOGIC|X-RAY|ANGIOGRAPHY|FLUOROSCOPY')
  GROUP BY proc.hadm_id
),
cohort_with_flags AS (
  SELECT
    c.hadm_id,
    c.los_group,
    IF(f.icu_flag IS NULL, 0, 1) AS icu_flag,
    IFNULL(ic.imaging_count, 0) AS imaging_count
  FROM cohort c
  LEFT JOIN icu_flags f
    ON c.hadm_id = f.hadm_id
  LEFT JOIN imaging_counts ic
    ON c.hadm_id = ic.hadm_id
)
SELECT
  los_group,
  icu_flag,
  COUNT(DISTINCT hadm_id) AS n_admissions,
  AVG(imaging_count) AS avg_imaging_per_adm
FROM cohort_with_flags
WHERE los_group IS NOT NULL
GROUP BY los_group, icu_flag
ORDER BY los_group, icu_flag;