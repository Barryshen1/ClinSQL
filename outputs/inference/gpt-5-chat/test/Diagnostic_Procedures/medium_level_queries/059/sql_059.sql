WITH hf_dx AS (
  SELECT
    di.subject_id,
    di.hadm_id,
    CASE
      WHEN MIN(CASE WHEN LOWER(dd.long_title) LIKE '%heart failure%' THEN seq_num END) = 1 THEN 'primary'
      ELSE 'secondary'
    END AS hf_type
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
    AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%heart failure%'
  GROUP BY di.subject_id, di.hadm_id
),
imaging_counts AS (
  SELECT
    pi.subject_id,
    pi.hadm_id,
    COUNT(*) AS img_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON pi.icd_code = dp.icd_code
    AND pi.icd_version = dp.icd_version
  WHERE LOWER(dp.long_title) LIKE '%x-ray%'
     OR LOWER(dp.long_title) LIKE '%radiology%'
     OR LOWER(dp.long_title) LIKE '%ct%'
     OR LOWER(dp.long_title) LIKE '%mri%'
     OR LOWER(dp.long_title) LIKE '%ultrasound%'
  GROUP BY pi.subject_id, pi.hadm_id
),
base AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    hf.hf_type,
    IFNULL(ic.img_count, 0) AS img_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN hf_dx hf
    ON a.subject_id = hf.subject_id
    AND a.hadm_id = hf.hadm_id
  LEFT JOIN imaging_counts ic
    ON a.subject_id = ic.subject_id
    AND a.hadm_id = ic.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 67 AND 77
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),
with_bucket AS (
  SELECT
    *,
    CASE
      WHEN los_days BETWEEN 1 AND 4 THEN 'LOS 1-4'
      WHEN los_days BETWEEN 5 AND 7 THEN 'LOS 5-7'
    END AS los_bucket
  FROM base
)
SELECT
  los_bucket,
  hf_type,
  APPROX_QUANTILES(img_count, 4)[OFFSET(1)] AS p25,
  APPROX_QUANTILES(img_count, 4)[OFFSET(2)] AS p50,
  APPROX_QUANTILES(img_count, 4)[OFFSET(3)] AS p75
FROM with_bucket
GROUP BY los_bucket, hf_type
ORDER BY los_bucket, hf_type;