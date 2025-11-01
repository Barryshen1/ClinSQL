WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_location,
    a.insurance,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON
    d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 58 AND 68
    AND a.insurance = 'Medicare'
    AND a.admission_location LIKE '%EMERGENCY%'
    AND d.seq_num = 1
    AND (
      LOWER(dd.long_title) LIKE '%femoral neck fracture%'
      OR d.icd_code IN ('S72001A', 'S72002A', 'S72009A')
    )
    AND a.hospital_expire_flag = 0
),

index_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    los_days,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM cohort
),

index_only AS (
  SELECT *
  FROM index_admissions
  WHERE rn = 1
),

readmissions AS (
  SELECT
    i.subject_id,
    i.hadm_id AS index_hadm_id,
    i.los_days AS index_los,
    CASE WHEN r.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS is_readmitted
  FROM index_only i
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` r
    ON i.subject_id = r.subject_id
    AND r.admittime > i.dischtime
    AND DATETIME_DIFF(r.admittime, i.dischtime, DAY) <= 30
    AND r.hospital_expire_flag = 0
    AND r.hadm_id <> i.hadm_id
)

SELECT
  AVG(is_readmitted) AS readmission_rate,
  APPROX_QUANTILES(CASE WHEN is_readmitted = 1 THEN index_los ELSE NULL END, 2)[OFFSET(1)] AS median_los_readmitted,
  APPROX_QUANTILES(CASE WHEN is_readmitted = 0 THEN index_los ELSE NULL END, 2)[OFFSET(1)] AS median_los_not_readmitted,
  AVG(CASE WHEN index_los > 8 THEN 1 ELSE 0 END) AS pct_stays_over_8_days
FROM readmissions;