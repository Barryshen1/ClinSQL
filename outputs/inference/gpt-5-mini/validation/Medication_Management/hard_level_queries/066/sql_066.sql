WITH transplant_admissions AS (
  -- Select admissions for male patients aged 43-53 with a transplant diagnosis
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code
    AND d.icd_version = di.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
    AND LOWER(di.long_title) LIKE '%transplant%'
  GROUP BY
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
),

med_scores AS (
  -- Compute medication complexity score = count distinct drugs in first 7 hospital days
  -- Include admittime and dischtime so downstream CTEs can reference them
  SELECT
    ta.subject_id,
    ta.hadm_id,
    ta.admittime,
    ta.dischtime,
    COALESCE(COUNT(DISTINCT LOWER(TRIM(prescriptions.drug))), 0) AS med_score,
    TIMESTAMP_DIFF(ta.dischtime, ta.admittime, DAY) AS los_days,
    ta.hospital_expire_flag
  FROM
    transplant_admissions ta
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` prescriptions
    ON prescriptions.hadm_id = ta.hadm_id
    -- use starttime or stoptime to determine if prescription falls in first 7 hospital days
    AND COALESCE(prescriptions.starttime, prescriptions.stoptime) IS NOT NULL
    AND COALESCE(prescriptions.starttime, prescriptions.stoptime) >= ta.admittime
    AND COALESCE(prescriptions.starttime, prescriptions.stoptime) < TIMESTAMP_ADD(ta.admittime, INTERVAL 7 DAY)
  GROUP BY
    ta.subject_id,
    ta.hadm_id,
    ta.admittime,
    ta.dischtime,
    ta.hospital_expire_flag
),

med_scores_with_readmit AS (
  -- Add 30-day readmission indicator
  SELECT
    m.*,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = m.subject_id
        AND a2.admittime > m.dischtime
        AND a2.admittime <= TIMESTAMP_ADD(m.dischtime, INTERVAL 30 DAY)
    ) THEN 1 ELSE 0 END AS readmit30
  FROM med_scores m
),

quartiled AS (
  -- Assign quartiles based on med_score (NTILE distributes admissions roughly equally)
  SELECT
    *,
    NTILE(4) OVER (ORDER BY med_score) AS quartile
  FROM med_scores_with_readmit
)

SELECT
  quartile,
  COUNT(*) AS n_admissions,
  ROUND(AVG(med_score), 3) AS mean_med_score,
  ROUND(AVG(los_days), 3) AS mean_los_days,
  ROUND(SUM(hospital_expire_flag) * 1.0 / COUNT(*) , 4) AS in_hospital_mortality_rate,
  ROUND(SUM(readmit30) * 1.0 / COUNT(*) , 4) AS readmit_30d_rate
FROM
  quartiled
GROUP BY
  quartile
ORDER BY
  quartile;