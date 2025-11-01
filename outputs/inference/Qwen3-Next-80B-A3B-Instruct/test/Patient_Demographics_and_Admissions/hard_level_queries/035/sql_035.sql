WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    p.gender,
    a.insurance,
    a.admission_location,
    d.long_title AS diagnosis,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_index
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'SNF'
    AND di.seq_num = 1
    AND (
      d.long_title LIKE '%urinary tract infection%'
      OR d.long_title LIKE '%cystitis%'
      OR d.long_title LIKE '%urethritis%'
      OR d.long_title LIKE '%urethral syndrome%'
      OR d.long_title LIKE '%bladder infection%'
      OR d.long_title LIKE '%pyelonephritis%'
      OR d.icd_code IN ('N39.0', 'N30.0', 'N30.1', 'N30.2', 'N30.3', 'N30.4', 'N30.8', 'N30.9',
                        'N31.0', 'N31.1', 'N31.2', 'N31.8', 'N31.9',
                        'N32.0', 'N32.1', 'N32.2', 'N32.3', 'N32.8', 'N32.9',
                        'N33.0', 'N33.1', 'N33.2', 'N33.3', 'N33.8', 'N33.9',
                        'N34.0', 'N34.1', 'N34.2', 'N34.3', 'N34.8', 'N34.9',
                        'N35.0', 'N35.1', 'N35.2', 'N35.3', 'N35.8', 'N35.9',
                        'N36.0', 'N36.1', 'N36.2', 'N36.8', 'N36.9')
    )
),
cohort_with_readmission AS (
  SELECT
    *,
    LEAD(admittime) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime,
    CASE
      WHEN dischtime IS NOT NULL
        AND LEAD(admittime) OVER (PARTITION BY subject_id ORDER BY admittime) IS NOT NULL
        AND DATE_DIFF(LEAD(admittime) OVER (PARTITION BY subject_id ORDER BY admittime), dischtime, DAY) <= 30
      THEN 1
      ELSE 0
    END AS readmitted_30d
  FROM cohort
)
SELECT
  AVG(readmitted_30d) AS readmission_rate_30d,
  PERCENTILE_CONT(CASE WHEN readmitted_30d = 1 THEN los_index END, 0.5) AS median_los_readmitted,
  PERCENTILE_CONT(CASE WHEN readmitted_30d = 0 THEN los_index END, 0.5) AS median_los_non_readmitted,
  AVG(CASE WHEN los_index > 6 THEN 1.0 ELSE 0.0 END) AS percent_stays_gt_6_days
FROM cohort_with_readmission;