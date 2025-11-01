WITH hemorrhagic_hadm AS (
  -- identify admissions with hemorrhagic stroke diagnoses (ICD-9/ICD-10 or textual match)
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dic
    ON d.icd_code = dic.icd_code AND d.icd_version = dic.icd_version
  WHERE
    (
      -- ICD-9 hemorrhagic codes (430,431,432) - match left 3 chars to allow decimals
      (d.icd_version = 9 AND SUBSTR(d.icd_code, 1, 3) IN ('430','431','432'))
      OR
      -- ICD-10 hemorrhagic codes I60, I61, I62 - match left 3 chars to allow subcodes
      (d.icd_version = 10 AND SUBSTR(UPPER(d.icd_code), 1, 3) IN ('I60','I61','I62'))
      OR
      -- textual match fallback (covers potential variations in d_icd_diagnoses.long_title)
      (LOWER(COALESCE(dic.long_title, '')) LIKE '%hemorrhag%' 
       OR LOWER(COALESCE(dic.long_title, '')) LIKE '%subarachn%'
       OR LOWER(COALESCE(dic.long_title, '')) LIKE '%intracerebr%'
       OR LOWER(COALESCE(dic.long_title, '')) LIKE '%cerebral hemorrh%')
    )
),

eligible_admissions AS (
  -- admissions for male patients aged 89-99 that have a hemorrhagic stroke diagnosis
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN hemorrhagic_hadm hh
    ON a.hadm_id = hh.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 89 AND 99
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),

med_counts_per_adm AS (
  -- count distinct drugs (normalized) started within first 7 days of admission
  SELECT
    ea.subject_id,
    ea.hadm_id,
    ea.admittime,
    ea.dischtime,
    ea.hospital_expire_flag,
    ea.anchor_age,
    COALESCE(
      (SELECT COUNT(DISTINCT LOWER(TRIM(drug)))
       FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
       WHERE pr.hadm_id = ea.hadm_id
         AND pr.drug IS NOT NULL
         AND pr.starttime IS NOT NULL
         AND pr.starttime >= ea.admittime
         AND pr.starttime <= TIMESTAMP_ADD(ea.admittime, INTERVAL 7 DAY)
      ), 0) AS med_count
  FROM eligible_admissions ea
),

med_quintile AS (
  -- assign quintiles by med_count (Q1 = lowest complexity)
  SELECT
    m.*,
    NTILE(5) OVER (ORDER BY med_count ASC, hadm_id ASC) AS med_quintile
  FROM med_counts_per_adm m
),

index_with_flags AS (
  -- compute LOS in days (fractional), and 30-day readmission flag per admission
  SELECT
    mq.*,
    SAFE_DIVIDE(TIMESTAMP_DIFF(dischtime, admittime, SECOND), 86400) AS los_days,
    CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END AS died_inpatient,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE a2.subject_id = mq.subject_id
          AND a2.admittime > mq.dischtime
          AND a2.admittime <= TIMESTAMP_ADD(mq.dischtime, INTERVAL 30 DAY)
      ) THEN 1 ELSE 0
    END AS readmit30
  FROM med_quintile mq
)

SELECT
  med_quintile AS quintile,                    -- 1 (lowest med complexity) .. 5 (highest)
  COUNT(*) AS n_admissions,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  -- median via APPROX_QUANTILES: with 2 quantiles -> array [min, median, max], median at OFFSET(1)
  APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los_days,
  ROUND(100.0 * SAFE_DIVIDE(SUM(died_inpatient), COUNT(*)), 2) AS inpatient_mortality_pct,
  ROUND(100.0 * SAFE_DIVIDE(SUM(readmit30), COUNT(*)), 2) AS readmit30_pct
FROM index_with_flags
GROUP BY med_quintile
ORDER BY med_quintile;