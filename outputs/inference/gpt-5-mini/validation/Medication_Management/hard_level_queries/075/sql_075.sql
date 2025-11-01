WITH cohort_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    -- LOS in days with fractional part
    SAFE_DIVIDE(TIMESTAMP_DIFF(a.dischtime, a.admittime, MINUTE), 1440.0) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      USING(subject_id)
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id AND a.subject_id = d.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 58 AND 68
    -- primary diagnosis = COPD / chronic obstructive pulmonary disease (string match on long_title)
    AND d.seq_num = 1
    AND (
      LOWER(dd.long_title) LIKE '%copd%'
      OR LOWER(dd.long_title) LIKE '%chronic obstructive pulmonary%'
      OR LOWER(dd.long_title) LIKE '%chronic obstructive%'
    )
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),

-- Gather medication events from three hosp medication tables; normalize med name and keep event time
medication_events AS (
  SELECT
    hadm_id,
    starttime AS evt_time,
    LOWER(TRIM(drug)) AS med_name
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE
    drug IS NOT NULL AND TRIM(drug) <> ''
  UNION ALL
  SELECT
    hadm_id,
    starttime AS evt_time,
    LOWER(TRIM(medication)) AS med_name
  FROM
    `physionet-data.mimiciv_3_1_hosp.pharmacy`
  WHERE
    medication IS NOT NULL AND TRIM(medication) <> ''
  UNION ALL
  SELECT
    hadm_id,
    charttime AS evt_time,
    LOWER(TRIM(medication)) AS med_name
  FROM
    `physionet-data.mimiciv_3_1_hosp.emar`
  WHERE
    medication IS NOT NULL AND TRIM(medication) <> ''
),

-- For each cohort admission, count distinct meds in first 72 hours
meds_per_admission AS (
  SELECT
    ca.hadm_id,
    COALESCE(COUNT(DISTINCT me.med_name), 0) AS complexity_score
  FROM
    cohort_admissions ca
    LEFT JOIN medication_events me
      ON me.hadm_id = ca.hadm_id
      AND me.evt_time BETWEEN ca.admittime AND TIMESTAMP_ADD(ca.admittime, INTERVAL 72 HOUR)
  GROUP BY
    ca.hadm_id
),

-- Combine cohort admissions with complexity score and compute 30-day readmission flag
admissions_with_metrics AS (
  SELECT
    ca.subject_id,
    ca.hadm_id,
    ca.admittime,
    ca.dischtime,
    ca.los_days,
    ca.hospital_expire_flag,
    COALESCE(mpa.complexity_score, 0) AS complexity_score,
    -- readmit30: 1 if any subsequent admission for same subject within 1-30 days after this discharge
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE
          a2.subject_id = ca.subject_id
          AND a2.admittime > ca.dischtime
          AND TIMESTAMP_DIFF(a2.admittime, ca.dischtime, DAY) BETWEEN 1 AND 30
      ) THEN 1
      ELSE 0
    END AS readmit30
  FROM
    cohort_admissions ca
    LEFT JOIN meds_per_admission mpa
      USING (hadm_id)
),

-- Assign tertiles by complexity_score (NTILE(3) over ordered complexity)
admissions_with_tertile AS (
  SELECT
    *,
    NTILE(3) OVER (ORDER BY complexity_score) AS tertile
  FROM
    admissions_with_metrics
)

-- Final aggregation per tertile
SELECT
  tertile,
  COUNT(*) AS n_admissions,
  MIN(complexity_score) AS complexity_min,
  MAX(complexity_score) AS complexity_max,
  ROUND(AVG(complexity_score), 2) AS complexity_mean,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(100.0 * AVG(CAST(hospital_expire_flag AS FLOAT64)), 2) AS mortality_percent,
  ROUND(100.0 * AVG(CAST(readmit30 AS FLOAT64)), 2) AS readmit_30day_percent
FROM
  admissions_with_tertile
GROUP BY
  tertile
ORDER BY
  tertile;