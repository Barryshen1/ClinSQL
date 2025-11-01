WITH cardiac_arrest_codes AS (
  -- Get ICD codes for cardiac arrest (ICD-9: 427.5, ICD-10: I46.x)
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    (icd_version = 9 AND icd_code = '4275') -- 427.5 stored as 4275
    OR (icd_version = 10 AND (icd_code LIKE 'I46%' OR icd_code LIKE 'I490%' OR icd_code LIKE 'I491%'))
),
cohort AS (
  -- Female, age 76-86, with cardiac arrest diagnosis
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN cardiac_arrest_codes c
    ON d.icd_code = c.icd_code AND d.icd_version = c.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 76 AND 86
),
med_complexity AS (
  -- Medication complexity score: count unique medications administered in first 7 days
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    COUNT(DISTINCT LOWER(e.medication)) AS med_complexity_score
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
    ON c.hadm_id = e.hadm_id
    AND e.charttime >= c.admittime
    AND e.charttime < DATETIME_ADD(c.admittime, INTERVAL 7 DAY)
  GROUP BY c.subject_id, c.hadm_id, c.admittime, c.dischtime, c.hospital_expire_flag
),
quintiles AS (
  -- Assign quintiles based on medication complexity score
  SELECT
    *,
    NTILE(5) OVER (ORDER BY med_complexity_score) AS complexity_quintile
  FROM med_complexity
),
los_and_readmit AS (
  -- Calculate LOS and 30-day readmission
  SELECT
    q.*,
    SAFE_DIVIDE(TIMESTAMP_DIFF(q.dischtime, q.admittime, SECOND), 86400) AS los_days,
    -- Find if readmitted within 30 days (exclude same hadm_id)
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE
        a2.subject_id = q.subject_id
        AND a2.hadm_id != q.hadm_id
        AND a2.admittime > q.dischtime
        AND a2.admittime <= DATETIME_ADD(q.dischtime, INTERVAL 30 DAY)
    ) THEN 1 ELSE 0 END AS readmit_30d
  FROM quintiles q
)
SELECT
  complexity_quintile,
  COUNT(*) AS patient_count,
  ROUND(AVG(med_complexity_score), 2) AS avg_complexity_score,
  MIN(med_complexity_score) AS min_complexity_score,
  MAX(med_complexity_score) AS max_complexity_score,
  ROUND(AVG(los_days), 2) AS avg_los_days,
  ROUND(100 * AVG(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), 2) AS in_hospital_mortality_pct,
  ROUND(100 * AVG(readmit_30d), 2) AS readmit_30d_pct
FROM los_and_readmit
GROUP BY complexity_quintile
ORDER BY complexity_quintile;