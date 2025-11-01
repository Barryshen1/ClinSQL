WITH index_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.insurance,
    a.admission_location,
    p.gender,
    -- calculate admission age
    p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS admission_age,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS admit_rank
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN (
    SELECT subject_id, hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    WHERE seq_num = 1
      AND (
        (icd_version = 9 AND icd_code = '5770')
        OR (icd_version = 10 AND icd_code LIKE 'K85%')
      )
  ) principal_dx
    ON a.subject_id = principal_dx.subject_id
   AND a.hadm_id = principal_dx.hadm_id
  WHERE p.gender = 'M'
    AND a.insurance = 'Medicare'
    AND p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 51 AND 61
    AND UPPER(a.admission_location) LIKE 'EMERGENCY%'
),
qualifying_index AS (
  SELECT * FROM index_admissions
  WHERE admit_rank = 1
),
next_admissions AS (
  SELECT
    qa.subject_id,
    qa.hadm_id AS index_hadm_id,
    MIN(a.admittime) AS next_admittime
  FROM qualifying_index qa
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON qa.subject_id = a.subject_id
   AND a.admittime > qa.dischtime
  GROUP BY qa.subject_id, qa.hadm_id
),
readmission_flags AS (
  SELECT
    qi.subject_id,
    qi.hadm_id,
    qi.admittime,
    qi.dischtime,
    -- LOS in days (fractional)
    DATETIME_DIFF(qi.dischtime, qi.admittime, SECOND) / 86400.0 AS los_days,
    CASE
      WHEN na.next_admittime IS NOT NULL
       AND DATETIME_DIFF(na.next_admittime, qi.dischtime, DAY) <= 30
      THEN 1 ELSE 0
    END AS readmit_flag
  FROM qualifying_index qi
  LEFT JOIN next_admissions na
    ON qi.subject_id = na.subject_id
   AND qi.hadm_id = na.index_hadm_id
)
SELECT
  COUNT(*) AS n_patients,
  ROUND(SUM(readmit_flag)/COUNT(*)*100,1) AS readmission_rate_pct,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_days_all,
  -- Median LOS by readmit group
  APPROX_QUANTILES(IF(readmit_flag=1, los_days, NULL), 100)[OFFSET(50)] AS median_los_days_readmitted,
  APPROX_QUANTILES(IF(readmit_flag=0, los_days, NULL), 100)[OFFSET(50)] AS median_los_days_not_readmitted,
  -- Percent > 9 days LOS by group
  ROUND(SUM(CASE WHEN readmit_flag = 1 AND los_days > 9 THEN 1 ELSE 0 END) /
        NULLIF(SUM(CASE WHEN readmit_flag = 1 THEN 1 ELSE 0 END),0) * 100,1) AS pct_gt9d_readmitted,
  ROUND(SUM(CASE WHEN readmit_flag = 0 AND los_days > 9 THEN 1 ELSE 0 END) /
        NULLIF(SUM(CASE WHEN readmit_flag = 0 THEN 1 ELSE 0 END),0) * 100,1) AS pct_gt9d_not_readmitted
FROM readmission_flags;