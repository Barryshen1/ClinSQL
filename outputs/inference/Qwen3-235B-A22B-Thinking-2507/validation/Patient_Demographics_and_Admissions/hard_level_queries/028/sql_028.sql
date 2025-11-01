WITH index_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age,
    DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / (24 * 60 * 60) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id AND d.seq_num = 1
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE 
    p.gender = 'F'
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'EMERGENCY ROOM ADMIT'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 55 AND 65
    AND LOWER(dd.long_title) LIKE '%cellulitis%'
    AND a.dischtime IS NOT NULL
),
index_admissions_with_readmission AS (
  SELECT 
    ia.*,
    EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE 
        a2.subject_id = ia.subject_id
        AND a2.admittime > ia.dischtime
        AND a2.admittime <= DATETIME_ADD(ia.dischtime, INTERVAL 30 DAY)
    ) AS readmitted
  FROM index_admissions ia
)
SELECT
  SUM(CAST(readmitted AS INT64)) * 1.0 / COUNT(*) AS readmission_rate,
  APPROX_QUANTILES(IF(readmitted, los, NULL), 100 IGNORE NULLS)[OFFSET(50)] AS median_los_readmitted,
  APPROX_QUANTILES(IF(NOT readmitted, los, NULL), 100 IGNORE NULLS)[OFFSET(50)] AS median_los_non_readmitted,
  SUM(IF(los > 7, 1, 0)) * 100.0 / COUNT(*) AS percent_index_stays_gt7
FROM index_admissions_with_readmission;