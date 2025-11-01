WITH eligible_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON dd.icd_code = di.icd_code AND dd.icd_version = di.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
    AND (
      LOWER(dd.long_title) LIKE '%transient%' AND LOWER(dd.long_title) LIKE '%ischemia%'
      OR LOWER(dd.long_title) LIKE '%tia%'
      OR di.icd_code LIKE 'G45%' OR di.icd_code LIKE '435%'
    )
),

imaging_by_hadm AS (
  SELECT
    pcd.hadm_id,
    COUNT(*) AS imaging_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pcd
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS dip
    ON dip.icd_code = pcd.icd_code
   AND dip.icd_version = pcd.icd_version
  WHERE
    LOWER(dip.long_title) LIKE '%imaging%'
    OR LOWER(dip.long_title) LIKE '%radiology%'
    OR LOWER(dip.long_title) LIKE '%ct%'
    OR LOWER(dip.long_title) LIKE '%mri%'
    OR LOWER(dip.long_title) LIKE '%x-ray%'
    OR LOWER(dip.long_title) LIKE '%ultrasound%'
  GROUP BY pcd.hadm_id
)

SELECT
  stay_group,
  AVG(imaging_count) AS mean_imaging_per_admission,
  MIN(imaging_count) AS min_imaging_per_admission,
  MAX(imaging_count) AS max_imaging_per_admission
FROM (
  SELECT
    e.hadm_id,
    CASE
      WHEN TIMESTAMP_DIFF(e.dischtime, e.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
      WHEN TIMESTAMP_DIFF(e.dischtime, e.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
      ELSE NULL
    END AS stay_group,
    COALESCE(imaging_by_hadm.imaging_count, 0) AS imaging_count
  FROM eligible_admissions e
  LEFT JOIN imaging_by_hadm
    ON imaging_by_hadm.hadm_id = e.hadm_id
) t
WHERE stay_group IS NOT NULL
GROUP BY stay_group
ORDER BY stay_group;