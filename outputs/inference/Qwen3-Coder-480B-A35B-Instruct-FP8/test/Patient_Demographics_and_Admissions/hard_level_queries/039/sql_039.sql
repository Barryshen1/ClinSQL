WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS admission_rank
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 65 AND 75
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'EMERGENCY ROOM'
    AND d.seq_num = 1
    AND LOWER(dd.long_title) LIKE '%acute respiratory failure%'
),

index_admissions AS (
  SELECT *
  FROM cohort
  WHERE admission_rank = 1
    AND hospital_expire_flag = 0
),

readmissions AS (
  SELECT
    ia.subject_id,
    ia.hadm_id AS index_hadm_id,
    ia.los AS index_los,
    CASE
      WHEN ra.hadm_id IS NOT NULL THEN 1
      ELSE 0
    END AS is_readmitted
  FROM
    index_admissions ia
  LEFT JOIN
    physionet-data.mimiciv_3_1_hosp.admissions ra
    ON ia.subject_id = ra.subject_id
    AND ra.admittime > ia.dischtime
    AND ra.admittime <= DATETIME_ADD(ia.dischtime, INTERVAL 30 DAY)
    AND ra.hospital_expire_flag = 0
)

SELECT
  -- 30-day readmission rate
  AVG(is_readmitted) AS readmission_rate,

  -- Median LOS for readmitted vs non-readmitted
  APPROX_QUANTILES(CASE WHEN is_readmitted = 1 THEN index_los ELSE NULL END, 2)[OFFSET(1)] AS median_los_readmitted,
  APPROX_QUANTILES(CASE WHEN is_readmitted = 0 THEN index_los ELSE NULL END, 2)[OFFSET(1)] AS median_los_not_readmitted,

  -- Percent with LOS > 9 days
  AVG(CASE WHEN index_los > 9 THEN 1 ELSE 0 END) * 100 AS percent_los_gt_9_days
FROM
  readmissions;