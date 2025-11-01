WITH base_patients AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
),
stroke_admissions AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN base_patients bp
    ON adm.subject_id = bp.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON adm.subject_id = di.subject_id AND adm.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE DATE_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 7
    AND (
      -- ICD-9 ischemic stroke patterns
      (di.icd_version = 9 AND REGEXP_CONTAINS(di.icd_code, r'^(433[0-9]1|434[0-9]1)$'))
      OR
      -- ICD-10 ischemic stroke
      (di.icd_version = 10 AND REGEXP_CONTAINS(di.icd_code, r'^I63'))
    )
),
imaging_counts AS (
  SELECT
    sa.subject_id,
    sa.hadm_id,
    COUNT(*) AS imaging_proc_count
  FROM stroke_admissions sa
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    ON sa.subject_id = pi.subject_id AND sa.hadm_id = pi.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dpi
    ON pi.icd_code = dpi.icd_code AND pi.icd_version = dpi.icd_version
  WHERE REGEXP_CONTAINS(LOWER(dpi.long_title), r'(ct|mri|magnetic resonance|tomography|ultrasound|x-ray|radiography)')
  GROUP BY sa.subject_id, sa.hadm_id
),
icu_flags AS (
  SELECT DISTINCT
    hadm_id,
    TRUE AS icu_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
)
SELECT
  CASE WHEN sa.los_days BETWEEN 1 AND 4 THEN 'LOS_1_4'
       WHEN sa.los_days BETWEEN 5 AND 7 THEN 'LOS_5_7' END AS los_group,
  IF(IFNULL(icuf.icu_flag, FALSE), 'ICU', 'NoICU') AS icu_group,
  AVG(ic.imaging_proc_count) AS mean_imaging_procs,
  MIN(ic.imaging_proc_count) AS min_imaging_procs,
  MAX(ic.imaging_proc_count) AS max_imaging_procs
FROM stroke_admissions sa
LEFT JOIN imaging_counts ic
  ON sa.subject_id = ic.subject_id AND sa.hadm_id = ic.hadm_id
LEFT JOIN icu_flags icuf
  ON sa.hadm_id = icuf.hadm_id
GROUP BY los_group, icu_group
ORDER BY los_group, icu_group;