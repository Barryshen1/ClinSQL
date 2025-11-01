WITH cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.anchor_age,
    pat.gender,
    adm.insurance,
    adm.admission_location,
    adm.admittime,
    adm.dischtime,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
    ON diag.icd_code = d_diag.icd_code
    AND diag.icd_version = d_diag.icd_version
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 65 AND 75
    AND adm.insurance = 'Medicare'
    AND adm.admission_location LIKE 'EMERGENCY%'
    AND diag.seq_num = 1
    AND LOWER(d_diag.long_title) LIKE '%acute respiratory failure%'
    AND adm.admittime IS NOT NULL
    AND adm.dischtime IS NOT NULL
),
readmission_flag AS (
  SELECT
    c.*,
    CASE 
      WHEN COUNTIF(
        adm2.admittime > c.dischtime 
        AND adm2.admittime <= DATETIME_ADD(c.dischtime, INTERVAL 30 DAY)
      ) > 0 THEN 1
      ELSE 0
    END AS readmitted_30d
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm2
    ON c.subject_id = adm2.subject_id
    AND c.hadm_id != adm2.hadm_id
  GROUP BY 
    c.subject_id, c.hadm_id, c.anchor_age, c.gender, c.insurance,
    c.admission_location, c.admittime, c.dischtime, c.los_days
),
metrics AS (
  SELECT
    SAFE_DIVIDE(SUM(readmitted_30d), COUNT(*)) AS readmission_rate_30d,
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_overall,
    -- median LOS for each group
    APPROX_QUANTILES(IF(readmitted_30d=1, los_days, NULL), 100)[OFFSET(50)] AS median_los_readmitted,
    APPROX_QUANTILES(IF(readmitted_30d=0, los_days, NULL), 100)[OFFSET(50)] AS median_los_nonreadmitted,
    SAFE_DIVIDE(COUNTIF(los_days > 9), COUNT(*)) AS pct_los_gt_9
  FROM readmission_flag
)
SELECT * FROM metrics;