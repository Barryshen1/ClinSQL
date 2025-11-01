WITH tia_female_50_60 AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON di.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND (
      (di.icd_version = 9 AND di.icd_code LIKE '435%')
      OR (di.icd_version = 10 AND di.icd_code LIKE 'G45%')
    )
),
los_with_group AS (
  SELECT
    t.subject_id,
    t.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 3 THEN 'LOS 1-3 days'
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 4 AND 7 THEN 'LOS 4-7 days'
      ELSE NULL
    END AS los_group
  FROM tia_female_50_60 t
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON t.subject_id = a.subject_id AND t.hadm_id = a.hadm_id
),
imaging_counts AS (
  SELECT
    pi.subject_id,
    pi.hadm_id,
    COUNT(*) AS imaging_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dpi
    ON pi.icd_code = dpi.icd_code AND pi.icd_version = dpi.icd_version
  WHERE LOWER(dpi.long_title) LIKE '%ct%'
     OR LOWER(dpi.long_title) LIKE '%mri%'
  GROUP BY pi.subject_id, pi.hadm_id
)
SELECT
  l.los_group,
  COUNT(DISTINCT l.subject_id) AS patient_count,
  ROUND(AVG(IFNULL(ic.imaging_count, 0)), 2) AS mean_ct_mri_per_adm
FROM los_with_group l
LEFT JOIN imaging_counts ic
  ON l.subject_id = ic.subject_id AND l.hadm_id = ic.hadm_id
WHERE l.los_group IS NOT NULL
GROUP BY l.los_group
ORDER BY l.los_group;