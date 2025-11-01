WITH tia_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      ON a.subject_id = dx.subject_id
      AND a.hadm_id = dx.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
      ON dx.icd_code = di.icd_code
      AND dx.icd_version = di.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
    AND LOWER(di.long_title) LIKE '%transient ischemic attack%'
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),
imaging_events AS (
  SELECT
    ha.hadm_id,
    -- count only radiology procedure codes
    COUNT(dh.code) AS imaging_count
  FROM
    tia_admissions ha
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.hcpcsevents` he
      ON ha.hadm_id = he.hadm_id
      AND DATE(he.chartdate) BETWEEN DATE(ha.admittime) AND DATE(ha.dischtime)
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` dh
      ON he.hcpcs_cd = CAST(dh.code AS STRING)
      AND dh.category = 'Radiology'
  GROUP BY
    ha.hadm_id
),
bucketed AS (
  SELECT
    ia.hadm_id,
    ia.los_days,
    ie.imaging_count,
    CASE
      WHEN ia.los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN ia.los_days BETWEEN 4 AND 7 THEN '4-7 days'
    END AS stay_bucket
  FROM
    tia_admissions ia
    JOIN imaging_events ie
      ON ia.hadm_id = ie.hadm_id
)
SELECT
  stay_bucket,
  ROUND(AVG(imaging_count), 2) AS mean_imaging_per_admission,
  MIN(imaging_count) AS min_imaging_per_admission,
  MAX(imaging_count) AS max_imaging_per_admission
FROM
  bucketed
GROUP BY
  stay_bucket
ORDER BY
  stay_bucket;