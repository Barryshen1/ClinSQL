WITH pe_admissions AS (
  -- admissions for PE among women aged 64-74
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      ON a.hadm_id = di.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
      ON di.icd_code = d.icd_code
         AND di.icd_version = d.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 64 AND 74
    -- look for pulmonary embolism in the diagnosis description
    AND LOWER(d.long_title) LIKE '%pulmonary%'
    AND LOWER(d.long_title) LIKE '%embol%'
  GROUP BY
    a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
),

meds_first24 AS (
  -- union prescriptions and pharmacy medication starts within first 24 hours of admission
  SELECT
    pa.hadm_id,
    LOWER(TRIM(medname)) AS medname
  FROM
    pe_admissions pa
  JOIN (
    -- prescriptions
    SELECT hadm_id, starttime, drug AS medname FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
    UNION ALL
    -- pharmacy table (some meds may appear here)
    SELECT hadm_id, starttime, medication AS medname FROM `physionet-data.mimiciv_3_1_hosp.pharmacy`
  ) meds
    ON meds.hadm_id = pa.hadm_id
    AND meds.medname IS NOT NULL
    AND TRIM(meds.medname) <> ''
    AND meds.starttime IS NOT NULL
    AND meds.starttime >= pa.admittime
    AND meds.starttime <= TIMESTAMP_ADD(pa.admittime, INTERVAL 24 HOUR)
),

med_counts AS (
  -- distinct medication count per admission in first 24 hours
  SELECT
    hadm_id,
    COUNT(DISTINCT medname) AS med_count
  FROM meds_first24
  GROUP BY hadm_id
),

cohort_with_med AS (
  -- combine cohort admissions with med counts and compute LOS and 30-day readmit flag
  SELECT
    pa.subject_id,
    pa.hadm_id,
    pa.admittime,
    pa.dischtime,
    COALESCE(mc.med_count, 0) AS med_count,
    -- LOS in days with fractional part
    ROUND(SAFE_DIVIDE(TIMESTAMP_DIFF(pa.dischtime, pa.admittime, SECOND), 86400.0), 2) AS los_days,
    pa.hospital_expire_flag,
    -- 30-day readmission flag: any subsequent admission for the same subject within 30 days after discharge
    IF (
      EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE a2.subject_id = pa.subject_id
          AND a2.admittime > pa.dischtime
          AND TIMESTAMP_DIFF(a2.admittime, pa.dischtime, DAY) <= 30
      ), 1, 0
    ) AS readmit_30d
  FROM
    pe_admissions pa
    LEFT JOIN med_counts mc
      ON pa.hadm_id = mc.hadm_id
),

ranked AS (
  -- assign tertiles across the cohort by med_count
  SELECT
    *,
    NTILE(3) OVER (ORDER BY med_count) AS med_tertile
  FROM
    cohort_with_med
)

-- Aggregate results by tertile
SELECT
  med_tertile AS tertile,
  COUNT(*) AS admissions,
  MIN(med_count) AS med_count_min,
  MAX(med_count) AS med_count_max,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(100.0 * SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*)), 2) AS in_hospital_mortality_pct,
  ROUND(100.0 * SAFE_DIVIDE(SUM(readmit_30d), COUNT(*)), 2) AS readmit_30d_pct
FROM
  ranked
GROUP BY
  med_tertile
ORDER BY
  med_tertile;