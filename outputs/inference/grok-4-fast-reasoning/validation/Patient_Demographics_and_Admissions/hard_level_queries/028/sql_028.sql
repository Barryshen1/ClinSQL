WITH index_cohort AS (
  SELECT DISTINCT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON a.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON diag.icd_code = dd.icd_code
    AND diag.icd_version = dd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 55 AND 65
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'EMERGENCY ROOM'
    AND diag.seq_num = 1
    AND LOWER(dd.long_title) LIKE '%cellulitis%'
),
cohort AS (
  SELECT
    ic.*,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE a2.subject_id = ic.subject_id
          AND a2.hadm_id != ic.hadm_id
          AND a2.admittime > ic.dischtime
          AND a2.admittime <= TIMESTAMP_ADD(ic.dischtime, INTERVAL 30 DAY)
      ) THEN 1
      ELSE 0
    END AS readmitted
  FROM index_cohort ic
)
SELECT
  (COUNTIF(readmitted = 1) * 100.0 / COUNT(*)) AS readmission_rate_pct,
  (SELECT APPROX_QUANTILES(los, 2)[OFFSET(1)]
   FROM cohort
   WHERE readmitted = 1) AS median_los_readmitted_days,
  (SELECT APPROX_QUANTILES(los, 2)[OFFSET(1)]
   FROM cohort
   WHERE readmitted = 0) AS median_los_nonreadmitted_days,
  (COUNTIF(los > 7) * 100.0 / COUNT(*)) AS pct_stays_gt7days
FROM cohort;