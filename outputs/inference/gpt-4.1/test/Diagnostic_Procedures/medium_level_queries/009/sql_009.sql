WITH cohort AS (
  -- Female patients age 44–54
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 44 AND 54
),
tia_admissions AS (
  -- Admissions with TIA diagnosis
  SELECT DISTINCT adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN cohort c ON adm.subject_id = c.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx ON adm.hadm_id = dx.hadm_id
  WHERE (
    (dx.icd_version = 10 AND REGEXP_CONTAINS(dx.icd_code, r'^G45')) OR
    (dx.icd_version = 9 AND REGEXP_CONTAINS(dx.icd_code, r'^435'))
  )
),
imaging_procs AS (
  -- Imaging procedures per admission
  SELECT proc.hadm_id, COUNT(*) AS imaging_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dproc
    ON proc.icd_code = dproc.icd_code AND proc.icd_version = dproc.icd_version
  WHERE LOWER(dproc.long_title) LIKE '%ct%'
     OR LOWER(dproc.long_title) LIKE '%mri%'
     OR LOWER(dproc.long_title) LIKE '%ultrasound%'
     OR LOWER(dproc.long_title) LIKE '%radiography%'
     OR LOWER(dproc.long_title) LIKE '%angiography%'
     OR LOWER(dproc.long_title) LIKE '%x-ray%'
     OR LOWER(dproc.long_title) LIKE '%pet%'
     OR LOWER(dproc.long_title) LIKE '%scan%'
  GROUP BY proc.hadm_id
),
icu_use AS (
  -- Admissions with ICU stay
  SELECT DISTINCT hadm_id, TRUE AS icu_used
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
admission_imaging AS (
  -- Combine all info per admission
  SELECT
    t.subject_id,
    t.hadm_id,
    TIMESTAMP_DIFF(t.dischtime, t.admittime, DAY) AS los_days,
    CASE
      WHEN TIMESTAMP_DIFF(t.dischtime, t.admittime, DAY) BETWEEN 1 AND 4 THEN '1-4'
      WHEN TIMESTAMP_DIFF(t.dischtime, t.admittime, DAY) BETWEEN 5 AND 7 THEN '5-7'
      ELSE NULL
    END AS los_group,
    IFNULL(ip.imaging_count, 0) AS imaging_count,
    IFNULL(iu.icu_used, FALSE) AS icu_used
  FROM tia_admissions t
  LEFT JOIN imaging_procs ip ON t.hadm_id = ip.hadm_id
  LEFT JOIN icu_use iu ON t.hadm_id = iu.hadm_id
  WHERE TIMESTAMP_DIFF(t.dischtime, t.admittime, DAY) BETWEEN 1 AND 7
)
SELECT
  los_group,
  icu_used,
  APPROX_QUANTILES(imaging_count, 4)[OFFSET(1)] AS p25,
  APPROX_QUANTILES(imaging_count, 4)[OFFSET(2)] AS p50,
  APPROX_QUANTILES(imaging_count, 4)[OFFSET(3)] AS p75,
  COUNT(*) AS n_admissions
FROM admission_imaging
WHERE los_group IS NOT NULL
GROUP BY los_group, icu_used
ORDER BY los_group, icu_used DESC;