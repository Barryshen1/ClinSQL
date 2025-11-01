WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS hosp_los,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    a.hadm_id = d.hadm_id AND d.seq_num = 1
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON
    d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'EMERGENCY ROOM'
    AND LOWER(dd.long_title) LIKE '%acute pancreatitis%'
),

index_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    hosp_los
  FROM (
    SELECT
      *,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
    FROM
      cohort
  )
  WHERE
    rn = 1
),

readmissions AS (
  SELECT
    ia.subject_id,
    ia.hadm_id AS index_hadm_id,
    ia.hosp_los AS index_los,
    CASE
      WHEN ra.hadm_id IS NOT NULL THEN 1
      ELSE 0
    END AS readmitted_30d
  FROM
    index_admissions ia
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` ra
  ON
    ia.subject_id = ra.subject_id
    AND ra.admittime > ia.dischtime
    AND ra.admittime <= DATETIME_ADD(ia.dischtime, INTERVAL 30 DAY)
)

SELECT
  readmitted_30d,
  COUNT(*) AS n_stays,
  APPROX_QUANTILES(index_los, 2)[OFFSET(1)] AS median_los,
  AVG(CASE WHEN index_los > 9 THEN 1 ELSE 0 END) * 100 AS pct_stays_over_9_days
FROM
  readmissions
GROUP BY
  readmitted_30d
ORDER BY
  readmitted_30d;