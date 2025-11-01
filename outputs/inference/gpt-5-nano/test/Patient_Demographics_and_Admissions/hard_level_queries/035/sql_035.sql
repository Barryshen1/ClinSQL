WITH cohort_index AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE p.gender = 'Male'
    AND p.anchor_age BETWEEN 68 AND 78
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'SNF'
    AND di.seq_num = 1
    AND REGEXP_CONTAINS(LOWER(dd.long_title), r'urinary tract infection')
),
indexed AS (
  SELECT
    ci.*,
    (SELECT MIN(a2.admittime)
     FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
     WHERE a2.subject_id = ci.subject_id
       AND a2.admittime > ci.dischtime) AS next_admittime
  FROM cohort_index ci
)
SELECT
  SAFE_DIVIDE(
    SUM(CASE WHEN next_admittime IS NOT NULL
              AND next_admittime <= TIMESTAMP_ADD(dischtime, INTERVAL 30 DAY) THEN 1 ELSE 0 END),
    COUNT(*)
  ) * 100.0 AS thirty_day_readmission_rate_percent,

  MEDIAN(CASE
           WHEN next_admittime IS NOT NULL
                AND next_admittime <= TIMESTAMP_ADD(dischtime, INTERVAL 30 DAY)
           THEN los_days
           ELSE NULL
         END) AS median_los_readmitted_days,

  MEDIAN(CASE
           WHEN next_admittime IS NULL
                OR next_admittime > TIMESTAMP_ADD(dischtime, INTERVAL 30 DAY)
           THEN los_days
           ELSE NULL
         END) AS median_los_nonreadmitted_days,

  100.0 * SUM(CASE WHEN los_days > 6 THEN 1 ELSE 0 END) / COUNT(*) AS percent_stays_gt_6
FROM indexed;