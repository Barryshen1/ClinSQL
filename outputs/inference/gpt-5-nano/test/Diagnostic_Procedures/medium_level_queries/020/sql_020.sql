WITH tia_admissions AS (
  SELECT DISTINCT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_adm
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    ON a.subject_id = diag.subject_id AND a.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON diag.icd_code = dd.icd_code AND diag.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%transient ischemic attack%'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 72 AND 82
)
, -- ICU presence per admission
icu_presence AS (
  SELECT hadm_id, 'Yes' AS icu_use
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY hadm_id
)
, -- Prepare admissions with LOS and ICU flag
admissions_with_los AS (
  SELECT
    t.hadm_id,
    t.admittime,
    t.dischtime,
    DATE_DIFF(DATE(t.dischtime), DATE(t.admittime), DAY) AS los_days,
    COALESCE(i.icu_use, 'No') AS icu_use
  FROM tia_admissions t
  LEFT JOIN icu_presence i ON t.hadm_id = i.hadm_id
)
SELECT
  CASE
    WHEN a.los_days BETWEEN 1 AND 3 THEN '1-3'
    WHEN a.los_days BETWEEN 4 AND 7 THEN '4-7'
    ELSE NULL
  END AS los_group,
  a.icu_use,
  COUNT(*) AS admission_count,
  AVG(p_imaging.imaging_per_admission) AS mean_imaging_per_admission
FROM admissions_with_los AS a
JOIN (
  -- Imaging count per admission (correlated per admission)
  SELECT ah.hadm_id,
         (
           SELECT COUNT(*)
           FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pc
           JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` ddi
             ON pc.icd_code = ddi.icd_code AND pc.icd_version = ddi.icd_version
           WHERE pc.hadm_id = ah.hadm_id
             AND (
               LOWER(ddi.long_title) LIKE '%imaging%'
               OR LOWER(ddi.long_title) LIKE '%ct%'
               OR LOWER(ddi.long_title) LIKE '%mri%'
               OR LOWER(ddi.long_title) LIKE '%x-ray%'
               OR LOWER(ddi.long_title) LIKE '%radiography%'
             )
         ) AS imaging_per_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS ah
) AS p_imaging ON a.hadm_id = p_imaging.hadm_id
WHERE a.los_days BETWEEN 1 AND 7
GROUP BY los_group, icu_use
ORDER BY los_group, icu_use;