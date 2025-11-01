WITH index_admissions AS (
  -- Select index admissions that meet the cohort criteria
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 76 AND 86
    AND LOWER(COALESCE(a.insurance, '')) LIKE '%medicare%'
    AND LOWER(COALESCE(a.admission_location, '')) LIKE '%transfer from hospital%'
    AND a.hospital_expire_flag = 0 -- exclude in-hospital deaths for index
    AND d.seq_num = 1 -- principal diagnosis
    AND (
      (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^410')) -- ICD-9 AMI codes starting with 410
      OR
      (d.icd_version = 10 AND REGEXP_CONTAINS(UPPER(d.icd_code), r'^I21')) -- ICD-10 I21*
    )
),
index_with_readmit AS (
  -- For each index admission, determine whether a readmission occurred within 30 days
  SELECT
    ia.*,
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = ia.subject_id
        AND a2.admittime > ia.dischtime
        AND a2.admittime <= TIMESTAMP_ADD(ia.dischtime, INTERVAL 30 DAY)
    ) AS readmitted_30d
  FROM index_admissions ia
),
agg AS (
  SELECT
    COUNT(*) AS total_index_admissions,
    SUM(CASE WHEN readmitted_30d THEN 1 ELSE 0 END) AS readmit_count,
    -- median LOS for readmitted (approximate)
    (SELECT
       APPROX_QUANTILES(los_days, 100)[OFFSET(50)]
     FROM index_with_readmit t
     WHERE t.readmitted_30d) AS median_los_readmitted_days,
    -- median LOS for not readmitted (approximate)
    (SELECT
       APPROX_QUANTILES(los_days, 100)[OFFSET(50)]
     FROM index_with_readmit t
     WHERE NOT t.readmitted_30d) AS median_los_not_readmitted_days,
    SUM(CASE WHEN los_days > 4 THEN 1 ELSE 0 END) AS count_los_gt_4
  FROM index_with_readmit
)

SELECT
  total_index_admissions,
  readmit_count,
  SAFE_DIVIDE(readmit_count, total_index_admissions) * 100.0 AS readmission_rate_pct_30d,
  median_los_readmitted_days,
  median_los_not_readmitted_days,
  SAFE_DIVIDE(count_los_gt_4, total_index_admissions) * 100.0 AS pct_index_los_gt_4_days
FROM agg;