WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 58 AND 68
    AND a.insurance = 'Medicare'
    AND UPPER(a.admission_location) LIKE '%EMERGENCY%'
    AND di.seq_num = 1
    AND (
      (di.icd_version = 9 AND di.icd_code LIKE '8200%') OR
      (di.icd_version = 10 AND di.icd_code LIKE 'S720%')
    )
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
index_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    los
  FROM (
    SELECT
      c.*,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
    FROM cohort c
  )
  WHERE rn = 1
),
readmission_flags AS (
  SELECT
    ia.subject_id,
    ia.hadm_id,
    ia.admittime,
    ia.dischtime,
    ia.los,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = ia.subject_id
        AND a2.hadm_id != ia.hadm_id
        AND a2.admittime > ia.dischtime
        AND a2.admittime <= DATETIME_ADD(ia.dischtime, INTERVAL 30 DAY)
    ) THEN 1 ELSE 0 END AS readmitted
  FROM index_admissions ia
)
SELECT
  COUNTIF(readmitted = 1) / COUNT(*) AS readmission_rate,
  APPROX_QUANTILES(IF(readmitted = 1, los, NULL), 2)[OFFSET(1)] AS median_los_readmitted,
  APPROX_QUANTILES(IF(readmitted = 0, los, NULL), 2)[OFFSET(1)] AS median_los_non_readmitted,
  COUNTIF(los > 8) / COUNT(*) AS pct_los_gt8days
FROM readmission_flags;