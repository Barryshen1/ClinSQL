WITH tia_principal AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.insurance,
    a.admission_location,
    p.anchor_age,
    p.gender,
    -- length of stay in fractional days
    TIMESTAMP_DIFF(a.dischtime, a.admittime, MINUTE) / 1440.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON dx.hadm_id = a.hadm_id
   AND dx.seq_num = 1  -- principal diagnosis
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddesc
    ON dx.icd_code = ddesc.icd_code
   AND dx.icd_version = ddesc.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 83 AND 93
    AND LOWER(a.insurance) LIKE '%medicare%'
    AND (
          LOWER(a.admission_location) LIKE '%ed%'
       OR LOWER(a.admission_location) LIKE '%emergency%'
    )
    -- exclude in-hospital deaths since they cannot be readmitted (explicit choice)
    AND a.hospital_expire_flag = 0
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    -- TIA principal diagnosis: ICD-9 435*, ICD-10 G45*, or description match
    AND (
         (dx.icd_version = 9 AND dx.icd_code LIKE '435%')
      OR (dx.icd_version = 10 AND dx.icd_code LIKE 'G45%')
      OR (ddesc.long_title IS NOT NULL AND LOWER(ddesc.long_title) LIKE '%transient ischemic attack%')
    )
),

-- For each index admission, find the earliest subsequent admission within 30 days (if any)
next_readmit AS (
  SELECT
    tp.hadm_id AS index_hadm_id,
    MIN(a2.admittime) AS next_admittime_within_30d
  FROM tia_principal tp
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a2
    ON a2.subject_id = tp.subject_id
   AND a2.hadm_id != tp.hadm_id
   AND a2.admittime > tp.dischtime
   AND a2.admittime <= TIMESTAMP_ADD(tp.dischtime, INTERVAL 30 DAY)
  GROUP BY tp.hadm_id
)

SELECT
  COUNT(*) AS n_index_admissions,
  SUM(CASE WHEN nr.next_admittime_within_30d IS NOT NULL THEN 1 ELSE 0 END) AS n_readmitted_within_30d,
  ROUND(100.0 * SUM(CASE WHEN nr.next_admittime_within_30d IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_readmitted_30d,
  -- median LOS among those readmitted (approximate)
  APPROX_QUANTILES( IF(nr.next_admittime_within_30d IS NOT NULL, tp.los_days, NULL), 2 )[OFFSET(1)] AS median_los_readmitted_days,
  -- median LOS among those NOT readmitted (approximate)
  APPROX_QUANTILES( IF(nr.next_admittime_within_30d IS NULL, tp.los_days, NULL), 2 )[OFFSET(1)] AS median_los_not_readmitted_days,
  -- percent of index stays > 10 days
  ROUND(100.0 * SUM(CASE WHEN tp.los_days > 10 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_index_los_gt_10_days
FROM tia_principal tp
LEFT JOIN next_readmit nr
  ON tp.hadm_id = nr.index_hadm_id;