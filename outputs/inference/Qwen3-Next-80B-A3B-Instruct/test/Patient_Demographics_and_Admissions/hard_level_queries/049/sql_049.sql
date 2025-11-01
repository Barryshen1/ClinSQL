WITH index_cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    p.dod,
    a.admission_location,
    a.insurance,
    di.long_title
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd di_c
    ON a.hadm_id = di_c.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses di
    ON di_c.icd_code = di.icd_code AND di_c.icd_version = di.icd_version
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 61 AND 71
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'SNF'
    AND di_c.seq_num = 1
    AND LOWER(di.long_title) LIKE '%acute kidney injury%'
    AND a.dischtime IS NOT NULL
    AND a.admittime IS NOT NULL
),

with_next_admission AS (
  SELECT *,
    LEAD(admittime) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime
  FROM index_cohort
),

readmission_flag AS (
  SELECT *,
    CASE 
      WHEN next_admittime IS NOT NULL 
        AND next_admittime <= DATE_ADD(dischtime, INTERVAL 30 DAY)
        AND hospital_expire_flag = 0  -- Only alive patients can be readmitted
      THEN 1 
      ELSE 0 
    END AS readmitted,
    DATE_DIFF(dischtime, admittime, DAY) AS index_los
  FROM with_next_admission
)

SELECT
  SUM(readmitted) * 100.0 / COUNT(*) AS readmission_rate_percent,
  APPROX_QUANTILES(CASE WHEN readmitted = 1 THEN index_los END, 2)[OFFSET(1)] AS median_los_readmitted,
  APPROX_QUANTILES(CASE WHEN readmitted = 0 THEN index_los END, 2)[OFFSET(1)] AS median_los_non_readmitted,
  SUM(CASE WHEN index_los > 6 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS percent_index_stays_gt_6_days
FROM readmission_flag;