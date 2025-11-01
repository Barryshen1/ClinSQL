WITH index_admissions AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    p.anchor_age,
    LOWER(adm.insurance) AS insurance,
    LOWER(adm.admission_location) AS admission_location,
    -- LOS in fractional days
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, MINUTE) / 1440.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      USING(subject_id)
    -- principal diagnosis (seq_num = 1)
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      ON adm.hadm_id = diag.hadm_id AND diag.seq_num = 1
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
      ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 50 AND 60
    AND LOWER(adm.insurance) LIKE '%medicare%'
    AND (
      LOWER(adm.admission_location) LIKE '%emergency%'
      OR LOWER(adm.admission_location) LIKE '%ed%'
    )
    -- Text-based filter for principal lower GI bleeding diagnoses.
    AND LOWER(d.long_title) LIKE '%gastrointestinal%hemorrhage%'
    AND (
      LOWER(d.long_title) LIKE '%lower%'
      OR LOWER(d.long_title) LIKE '%rectal%'
      OR LOWER(d.long_title) LIKE '%colon%'
      OR LOWER(d.long_title) LIKE '%colonic%'
      OR LOWER(d.long_title) LIKE '%sigmoid%'
    )
),

-- Determine if each index admission has a readmission within 30 days after discharge
index_with_readmit_flag AS (
  SELECT
    ia.*,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = ia.subject_id
        AND a2.admittime > ia.dischtime
        AND a2.admittime <= TIMESTAMP_ADD(ia.dischtime, INTERVAL 30 DAY)
    ) THEN 1 ELSE 0 END AS readmit_30_flag
  FROM index_admissions ia
)

-- Final aggregations:
SELECT
  'Overall' AS group_label,
  COUNT(*) AS n_index_admissions,
  SUM(readmit_30_flag) AS n_readmitted_within_30d,
  SAFE_DIVIDE(100.0 * SUM(readmit_30_flag), COUNT(*)) AS pct_readmitted_30d,
  -- overall median LOS (approx)
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_days_overall,
  SAFE_DIVIDE(100.0 * SUM(CASE WHEN los_days > 6 THEN 1 ELSE 0 END), COUNT(*)) AS pct_los_gt_6d_overall
FROM index_with_readmit_flag

UNION ALL

SELECT
  CASE WHEN readmit_30_flag = 1 THEN 'Readmitted within 30 days' ELSE 'Not readmitted within 30 days' END AS group_label,
  COUNT(*) AS n_index_admissions,
  SUM(readmit_30_flag) AS n_readmitted_within_30d,
  SAFE_DIVIDE(100.0 * SUM(readmit_30_flag), COUNT(*)) AS pct_readmitted_30d,
  -- median LOS per group (approx)
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_days_overall,
  SAFE_DIVIDE(100.0 * SUM(CASE WHEN los_days > 6 THEN 1 ELSE 0 END), COUNT(*)) AS pct_los_gt_6d_overall
FROM index_with_readmit_flag
GROUP BY readmit_30_flag
ORDER BY group_label DESC;