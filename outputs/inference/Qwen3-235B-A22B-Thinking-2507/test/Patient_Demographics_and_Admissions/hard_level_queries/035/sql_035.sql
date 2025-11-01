WITH base_index AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / (24 * 60 * 60.0) AS index_los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE 
    p.gender = 'M'
    AND a.insurance = 'Medicare'
    AND (LOWER(a.admission_location) LIKE '%skilled nursing facility%' OR LOWER(a.admission_location) LIKE '%snf%')
    AND d.seq_num = 1
    AND LOWER(dd.long_title) LIKE '%urinary tract infection%'
    AND a.dischtime IS NOT NULL
    AND (
      p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)
    ) BETWEEN 68 AND 78
),
readmission_flags AS (
  SELECT 
    i.hadm_id,
    i.index_los_days,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE 
          a2.subject_id = i.subject_id
          AND a2.admittime > i.dischtime
          AND a2.admittime <= i.dischtime + INTERVAL '30' DAY
      ) THEN 1 
      ELSE 0 
    END AS readmitted
  FROM base_index i
)
SELECT
  SUM(readmitted) * 1.0 / COUNT(*) AS readmission_rate,
  APPROX_QUANTILES(CASE WHEN readmitted = 1 THEN index_los_days END, 100)[OFFSET(50)] AS median_los_readmitted,
  APPROX_QUANTILES(CASE WHEN readmitted = 0 THEN index_los_days END, 100)[OFFSET(50)] AS median_los_non_readmitted,
  SUM(CASE WHEN index_los_days > 6 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS percent_stays_gt6
FROM readmission_flags;