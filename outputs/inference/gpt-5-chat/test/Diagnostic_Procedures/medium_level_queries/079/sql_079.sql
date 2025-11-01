WITH lgib_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    -- determine LOS in days
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days,
    -- primary vs secondary LGIB indicator
    MIN(CASE WHEN di.seq_num = 1 THEN 1 ELSE 2 END) AS diagnosis_priority
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.subject_id = di.subject_id
    AND a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
    AND di.icd_version = dd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 71 AND 81
    AND (
      LOWER(dd.long_title) LIKE '%lower gastrointestinal%'
      OR LOWER(dd.long_title) LIKE '%lgib%'
      OR LOWER(dd.long_title) LIKE '%lower gi bleed%'
      OR (LOWER(dd.long_title) LIKE '%hemorrhage%' AND LOWER(dd.long_title) LIKE '%lower%')
    )
  GROUP BY a.subject_id, a.hadm_id, los_days
),
imaging_counts AS (
  SELECT
    h.subject_id,
    h.hadm_id,
    COUNT(*) AS imaging_count
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` dh
    ON h.hcpcs_cd = dh.code
  WHERE LOWER(dh.short_description) LIKE '%ct%'
     OR LOWER(dh.short_description) LIKE '%x-ray%'
     OR LOWER(dh.short_description) LIKE '%radiography%'
  GROUP BY h.subject_id, h.hadm_id
),
cohort AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    CASE WHEN l.los_days BETWEEN 1 AND 3 THEN '1-3 days'
         WHEN l.los_days BETWEEN 4 AND 7 THEN '4-7 days'
    END AS los_group,
    CASE WHEN l.diagnosis_priority = 1 THEN 'Primary' ELSE 'Secondary' END AS diagnosis_type,
    COALESCE(i.imaging_count, 0) AS imaging_count
  FROM lgib_admissions l
  LEFT JOIN imaging_counts i
    ON l.subject_id = i.subject_id
    AND l.hadm_id = i.hadm_id
  WHERE l.los_days BETWEEN 1 AND 7 -- only include desired LOS range
)
SELECT
  los_group,
  diagnosis_type,
  ROUND(AVG(imaging_count),2) AS mean_imaging_per_adm,
  COUNT(*) AS n_admissions
FROM cohort
GROUP BY los_group, diagnosis_type
ORDER BY los_group, diagnosis_type;