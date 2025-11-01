WITH eligible_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 67 AND 77
    AND a.dischtime IS NOT NULL
),

-- LOS bucket per admission: 1-4 days vs 5-7 days
los_buckets AS (
  SELECT
    hadm_id,
    CASE
      WHEN los_days BETWEEN 1 AND 4 THEN '1-4'
      WHEN los_days BETWEEN 5 AND 7 THEN '5-7'
      ELSE 'OTHER'
    END AS los_bucket
  FROM eligible_admissions
),

-- HF classification per admission: primary vs secondary (based on HF ICD long_title)
hf_classification AS (
  SELECT
    di.hadm_id,
    CASE WHEN MIN(di.seq_num) = 1 THEN 'primary'
         ELSE 'secondary'
    END AS hf_group
  FROM eligible_admissions e
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON e.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dld
    ON di.icd_code = dld.icd_code AND di.icd_version = dld.icd_version
  WHERE LOWER(dld.long_title) LIKE '%heart failure%'
  GROUP BY di.hadm_id
),

-- Imaging counts per admission (ICU procedures that look like imaging)
imaging_counts AS (
  SELECT
    e.hadm_id,
    SUM(
      CASE
        WHEN LOWER(ii.label) LIKE '%ct%'        THEN 1
        WHEN LOWER(ii.label) LIKE '%mri%'       THEN 1
        WHEN LOWER(ii.label) LIKE '%x-ray%'     THEN 1
        WHEN LOWER(ii.label) LIKE '%radiograph%' THEN 1
        WHEN LOWER(ii.label) LIKE '%ultrasound%' THEN 1
        WHEN LOWER(ii.label) LIKE '%imaging%'    THEN 1
        ELSE 0
      END
    ) AS imaging_count
  FROM eligible_admissions AS e
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS ic ON e.hadm_id = ic.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
    ON ic.hadm_id = pe.hadm_id AND ic.stay_id = pe.stay_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS ii
    ON pe.itemid = ii.itemid
  GROUP BY e.hadm_id
)

-- Compute quartiles per (HF type, LOS bucket) using approximate quartiles
, stats AS (
  SELECT
    hf.hf_group AS heart_failure_type,
    lb.los_bucket AS hospital_los_days,
    APPROX_QUANTILES(ic.imaging_count, 4) AS quantiles
  FROM imaging_counts ic
  JOIN hf_classification hf ON ic.hadm_id = hf.hadm_id
  JOIN los_buckets lb ON ic.hadm_id = lb.hadm_id
  WHERE lb.los_bucket IN ('1-4', '5-7')  -- limit to requested buckets
  GROUP BY hf.hf_group, lb.los_bucket
)

SELECT
  heart_failure_type,
  hospital_los_days,
  SAFE_CAST(quantiles[OFFSET(1)] AS INT64) AS p25,
  SAFE_CAST(quantiles[OFFSET(2)] AS INT64) AS p50,
  SAFE_CAST(quantiles[OFFSET(3)] AS INT64) AS p75
FROM stats
ORDER BY heart_failure_type, hospital_los_days;