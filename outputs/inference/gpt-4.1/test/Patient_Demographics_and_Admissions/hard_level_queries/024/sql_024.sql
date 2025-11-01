WITH ischemic_stroke_icd AS (
  -- List of ICD codes for ischemic stroke (ICD-9 and ICD-10)
  SELECT '433' AS icd_code, 9 AS icd_version UNION ALL
  SELECT '434' AS icd_code, 9 AS icd_version UNION ALL
  SELECT '436' AS icd_code, 9 AS icd_version UNION ALL
  SELECT 'I63' AS icd_code, 10 AS icd_version UNION ALL
  SELECT 'I65' AS icd_code, 10 AS icd_version UNION ALL
  SELECT 'I66' AS icd_code, 10 AS icd_version UNION ALL
  SELECT 'I69.3' AS icd_code, 10 AS icd_version
),
index_admissions AS (
  -- Find index admissions for male Medicare patients age 76-86 admitted from ED with principal ischemic stroke
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    a.insurance,
    a.admission_location,
    p.anchor_age,
    p.gender,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS rn,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
    JOIN physionet-data.mimiciv_3_1_hosp.patients p ON a.subject_id = p.subject_id
    JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON a.hadm_id = d.hadm_id
    JOIN ischemic_stroke_icd icd
      ON d.icd_version = icd.icd_version
      AND (
        -- For ICD-9, match first 3 digits
        (d.icd_version = 9 AND LEFT(d.icd_code, 3) = icd.icd_code)
        -- For ICD-10, match prefix
        OR (d.icd_version = 10 AND LEFT(d.icd_code, LENGTH(icd.icd_code)) = icd.icd_code)
      )
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 76 AND 86
    AND a.insurance = 'Medicare'
    AND (
      LOWER(a.admission_location) LIKE '%emergency%'
      OR LOWER(a.admission_location) LIKE '%ed%'
    )
    AND d.seq_num = 1
),
first_index_admissions AS (
  -- Only the first qualifying admission per patient
  SELECT *
  FROM index_admissions
  WHERE rn = 1
    AND (hospital_expire_flag = 0 OR hospital_expire_flag IS NULL)
    AND (deathtime IS NULL OR deathtime > dischtime)
),
readmissions AS (
  -- Find 30-day readmissions for each index admission
  SELECT
    idx.subject_id,
    idx.hadm_id AS index_hadm_id,
    idx.dischtime AS index_dischtime,
    a.hadm_id AS readmit_hadm_id,
    a.admittime AS readmit_admittime
  FROM
    first_index_admissions idx
    JOIN physionet-data.mimiciv_3_1_hosp.admissions a
      ON idx.subject_id = a.subject_id
      AND a.admittime > idx.dischtime
      AND a.admittime <= TIMESTAMP_ADD(idx.dischtime, INTERVAL 30 DAY)
),
final_cohort AS (
  -- Mark readmission status for each index admission
  SELECT
    idx.subject_id,
    idx.hadm_id,
    idx.admittime,
    idx.dischtime,
    idx.los,
    CASE WHEN r.readmit_hadm_id IS NOT NULL THEN 1 ELSE 0 END AS readmitted
  FROM
    first_index_admissions idx
    LEFT JOIN (
      SELECT subject_id, index_hadm_id, MIN(readmit_hadm_id) AS readmit_hadm_id
      FROM readmissions
      GROUP BY subject_id, index_hadm_id
    ) r
    ON idx.subject_id = r.subject_id AND idx.hadm_id = r.index_hadm_id
)
SELECT
  COUNT(*) AS n_index_admissions,
  ROUND(100.0 * SUM(readmitted) / COUNT(*), 2) AS readmission_rate_percent,
  ROUND(APPROX_QUANTILES(los, 2)[OFFSET(1)], 2) AS median_los,
  readmitted,
  ROUND(100.0 * SUM(CASE WHEN los > 5 THEN 1 ELSE 0 END) / COUNT(*), 2) AS percent_los_gt_5_days
FROM final_cohort
GROUP BY readmitted
ORDER BY readmitted DESC;