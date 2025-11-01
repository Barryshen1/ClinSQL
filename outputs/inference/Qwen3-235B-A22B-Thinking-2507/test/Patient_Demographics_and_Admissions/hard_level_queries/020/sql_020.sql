WITH index_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / (24*60*60.0) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id AND a.subject_id = d.subject_id
  WHERE
    p.gender = 'F'
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'TRANSFER FROM HOSPITAL'
    AND d.seq_num = 1
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '410%')
      OR (d.icd_version = 10 AND d.icd_code LIKE 'I21%')
    )
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 76 AND 86
    AND a.dischtime IS NOT NULL
),
index_admissions_with_readmitted AS (
  SELECT
    i.*,
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = i.subject_id
        AND a2.admittime > i.dischtime
        AND a2.admittime <= i.dischtime + INTERVAL '30' DAY
        AND a2.hadm_id != i.hadm_id
    ) AS readmitted
  FROM index_admissions i
)
SELECT
  COUNTIF(readmitted) * 1.0 / COUNT(*) AS readmission_rate,
  APPROX_QUANTILES(IF(readmitted, los, NULL), 100)[OFFSET(50)] AS median_los_readmitted,
  APPROX_QUANTILES(IF(NOT readmitted, los, NULL), 100)[OFFSET(50)] AS median_los_not_readmitted,
  COUNTIF(los > 4) * 100.0 / COUNT(*) AS percent_stays_gt4
FROM index_admissions_with_readmitted;