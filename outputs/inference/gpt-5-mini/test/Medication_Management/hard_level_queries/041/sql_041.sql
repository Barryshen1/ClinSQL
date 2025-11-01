WITH
-- 1) Base cohort: male patients age 40-50 with a heart-failure diagnosis on the admission
hf_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 40 AND 50
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
        ON d.icd_code = di.icd_code
       AND d.icd_version = di.icd_version
      WHERE
        d.hadm_id = a.hadm_id
        AND LOWER(di.long_title) LIKE '%heart failure%'
    )
),

-- 2) Medication metrics in the first 7 days after admission (using prescriptions)
meds_7d AS (
  SELECT
    h.hadm_id,
    h.subject_id,
    COALESCE(COUNT(DISTINCT LOWER(p.drug)), 0) AS distinct_drugs,
    COALESCE(COUNT(DISTINCT p.route), 0) AS distinct_routes,
    COALESCE(SUM(COALESCE(p.doses_per_24_hrs, 0)), 0) AS total_doses_per_24hrs
  FROM
    hf_admissions h
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  ON
    p.hadm_id = h.hadm_id
    AND p.starttime IS NOT NULL
    AND p.starttime >= h.admittime
    AND p.starttime < TIMESTAMP_ADD(h.admittime, INTERVAL 7 DAY)
  GROUP BY
    h.hadm_id,
    h.subject_id
),

-- 3) Combine meds with admission info, compute score, LOS, 30-day readmit flag
scored_admissions AS (
  SELECT
    h.hadm_id,
    h.subject_id,
    h.admittime,
    h.dischtime,
    h.hospital_expire_flag,
    COALESCE(m.distinct_drugs, 0) AS distinct_drugs,
    COALESCE(m.distinct_routes, 0) AS distinct_routes,
    COALESCE(m.total_doses_per_24hrs, 0) AS total_doses_per_24hrs,
    -- Medication complexity score definition (documented in reasoning)
    (COALESCE(m.distinct_drugs, 0)
     + COALESCE(m.distinct_routes, 0)
     + COALESCE(m.total_doses_per_24hrs, 0)
    ) AS med_score,
    -- LOS in fractional days
    TIMESTAMP_DIFF(h.dischtime, h.admittime, SECOND) / 86400.0 AS los_days,
    -- 30-day readmission flag (exists another admission for same subject within 30 days after discharge)
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = h.subject_id
        AND a2.admittime > h.dischtime
        AND a2.admittime <= TIMESTAMP_ADD(h.dischtime, INTERVAL 30 DAY)
    ) THEN 1 ELSE 0 END AS readmit30_flag
  FROM
    hf_admissions h
  LEFT JOIN
    meds_7d m
  ON h.hadm_id = m.hadm_id
),

-- 4) Assign quintiles across the cohort based on med_score
quintiled AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY med_score) AS med_score_quintile
  FROM
    scored_admissions
)

-- 5) Aggregate by quintile and produce required metrics
SELECT
  med_score_quintile AS quintile,
  COUNT(DISTINCT subject_id) AS patient_count,               -- unique patients in quintile
  COUNT(DISTINCT hadm_id) AS admission_count,                -- admissions in quintile (available)
  MIN(med_score) AS score_min,
  MAX(med_score) AS score_max,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(100.0 * AVG(CAST(hospital_expire_flag AS FLOAT64)), 2) AS pct_in_hospital_mortality,
  ROUND(100.0 * AVG(CAST(readmit30_flag AS FLOAT64)), 2) AS pct_30d_readmission
FROM
  quintiled
GROUP BY
  med_score_quintile
ORDER BY
  med_score_quintile;