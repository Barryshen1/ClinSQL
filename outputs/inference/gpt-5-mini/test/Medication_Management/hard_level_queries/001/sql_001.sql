WITH cardiac_admissions AS (
  -- Admissions for female patients age 76-86 that have a cardiac arrest diagnosis
  SELECT
    a.*
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    -- female patients (allow 'F' or 'FEMALE' etc.)
    UPPER(p.gender) LIKE 'F%'
    AND p.anchor_age BETWEEN 76 AND 86
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
        AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%cardiac arrest%'
    )
),

med_counts AS (
  -- For each index admission compute medication complexity (count distinct prescriptions.drug within first 7 days),
  -- LOS in days, mortality flag, and 30-day readmission flag.
  SELECT
    ca.*,
    COALESCE((
      SELECT COUNT(DISTINCT pr.drug)
      FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
      WHERE pr.hadm_id = ca.hadm_id
        AND pr.starttime IS NOT NULL
        AND pr.starttime >= ca.admittime
        AND pr.starttime < TIMESTAMP_ADD(ca.admittime, INTERVAL 7 DAY)
    ), 0) AS med_count,
    -- LOS in days (fractional)
    TIMESTAMP_DIFF(ca.dischtime, ca.admittime, SECOND) / 86400.0 AS los_days,
    ca.hospital_expire_flag AS mortality,
    -- 30-day readmission flag (true if any subsequent admission for same subject within 30 days after discharge)
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = ca.subject_id
        AND a2.admittime > ca.dischtime
        AND a2.admittime <= TIMESTAMP_ADD(ca.dischtime, INTERVAL 30 DAY)
    ) AS readmit30
  FROM cardiac_admissions ca
),

quintiled AS (
  -- Assign medication-complexity quintiles across the cohort (admission-level)
  SELECT
    *,
    NTILE(5) OVER (ORDER BY med_count, hadm_id) AS med_quintile
  FROM med_counts
)

SELECT
  med_quintile AS quintile,
  COUNT(*) AS patient_count,                                   -- number of admissions in the quintile
  ROUND(AVG(med_count), 2) AS avg_med_score,
  MIN(med_count) AS min_med_score,
  MAX(med_count) AS max_med_score,
  ROUND(AVG(los_days), 2) AS avg_los_days,
  ROUND(100.0 * SUM(IF(mortality = 1, 1, 0)) / COUNT(*), 2) AS pct_inhospital_mortality,
  ROUND(100.0 * SUM(IF(readmit30, 1, 0)) / COUNT(*), 2) AS pct_30day_readmit
FROM quintiled
GROUP BY med_quintile
ORDER BY med_quintile;