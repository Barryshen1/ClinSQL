WITH principal_uti_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.insurance,
    a.admission_location,
    p.gender,
    p.anchor_age,
    d.icd_code,
    d.icd_version
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 60 AND 70
    AND a.insurance = 'Medicare'
    AND LOWER(a.admission_location) LIKE '%emergency%'
    AND d.seq_num = 1
    AND (
      (d.icd_version = 9 AND d.icd_code = '5990') OR
      (d.icd_version = 10 AND d.icd_code = 'N390')
    )
    AND a.hospital_expire_flag = 0
),

readmissions AS (
  SELECT
    idx.subject_id,
    idx.hadm_id AS index_hadm_id,
    idx.admittime AS index_admittime,
    idx.dischtime AS index_dischtime,
    DATETIME_DIFF(idx.dischtime, idx.admittime, DAY) AS index_los,
    MIN(next.admittime) AS readmit_admittime,
    MIN(next.hadm_id) AS readmit_hadm_id
  FROM
    principal_uti_admissions idx
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` next
      ON idx.subject_id = next.subject_id
      AND next.admittime > idx.dischtime
      AND DATETIME_DIFF(next.admittime, idx.dischtime, DAY) <= 30
      AND next.hadm_id != idx.hadm_id
      AND next.hospital_expire_flag = 0
  GROUP BY
    idx.subject_id, idx.hadm_id, idx.admittime, idx.dischtime
),

final AS (
  SELECT
    *,
    CASE WHEN readmit_hadm_id IS NOT NULL THEN 1 ELSE 0 END AS was_readmitted,
    CASE WHEN index_los > 9 THEN 1 ELSE 0 END AS los_gt_9
  FROM
    readmissions
),

-- Median LOS for readmitted
median_los_readmitted AS (
  SELECT
    APPROX_QUANTILES(index_los, 2)[OFFSET(1)] AS median_los_readmitted
  FROM final
  WHERE was_readmitted = 1
),

-- Median LOS for non-readmitted
median_los_nonreadmitted AS (
  SELECT
    APPROX_QUANTILES(index_los, 2)[OFFSET(1)] AS median_los_nonreadmitted
  FROM final
  WHERE was_readmitted = 0
)

SELECT
  COUNT(*) AS n_index_admissions,
  SUM(was_readmitted) AS n_readmitted,
  ROUND(SUM(was_readmitted) / COUNT(*) * 100, 2) AS readmission_rate_percent,

  -- Median LOS for readmitted
  (SELECT median_los_readmitted FROM median_los_readmitted) AS median_los_readmitted,
  -- Median LOS for non-readmitted
  (SELECT median_los_nonreadmitted FROM median_los_nonreadmitted) AS median_los_nonreadmitted,

  -- Percent with LOS > 9 days
  ROUND(SUM(CASE WHEN was_readmitted = 1 THEN los_gt_9 ELSE 0 END) / NULLIF(SUM(was_readmitted),0) * 100, 2) AS pct_los_gt_9_readmitted,
  ROUND(SUM(CASE WHEN was_readmitted = 0 THEN los_gt_9 ELSE 0 END) / NULLIF(COUNT(*) - SUM(was_readmitted),0) * 100, 2) AS pct_los_gt_9_nonreadmitted

FROM
  final
;