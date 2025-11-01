WITH index_admissions AS (
  SELECT
    A.subject_id,
    A.hadm_id,
    A.admittime,
    A.dischtime,
    TIMESTAMP_DIFF(A.dischtime, A.admittime, DAY) AS los,
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` B
      WHERE B.subject_id = A.subject_id
        AND B.admittime > A.dischtime
        AND B.admittime <= TIMESTAMP_ADD(A.dischtime, INTERVAL 30 DAY)
    ) AS readmitted_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` A
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` P
    ON P.subject_id = A.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` D
    ON D.hadm_id = A.hadm_id
   AND D.seq_num = 1
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` DD
    ON DD.icd_code = D.icd_code
   AND DD.icd_version = D.icd_version
  WHERE P.gender = 'M'
    AND P.anchor_age BETWEEN 65 AND 75
    AND A.insurance = 'Medicare'
    AND A.admission_location LIKE 'EMERGENCY%'
    AND LOWER(DD.long_title) LIKE '%acute respiratory failure%'
)
SELECT
  -- overall 30-day readmission rate by group
  ROUND(
    100.0 * SUM(CAST(readmitted_flag AS INT64)) / COUNT(*)
  , 2) AS readmission_rate_percent,
  readmitted_flag,
  COUNT(*) AS n_admissions,
  APPROX_QUANTILES(los, 2)[OFFSET(1)] AS median_los_days,
  ROUND(
    100.0 * SUM(CASE WHEN los > 9 THEN 1 ELSE 0 END) / COUNT(*)
  , 2) AS pct_los_gt_9
FROM index_admissions
GROUP BY readmitted_flag
ORDER BY readmitted_flag DESC;