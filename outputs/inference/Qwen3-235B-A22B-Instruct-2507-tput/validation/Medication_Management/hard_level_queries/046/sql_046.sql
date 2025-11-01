WITH patient_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    -- Compute age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 45 AND 55
),

-- Identify injury-related ICD-10 codes (S00-T98)
injury_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses
  WHERE icd_version = 10
    AND (
      SUBSTR(icd_code, 1, 1) = 'S'
      OR (
        SUBSTR(icd_code, 1, 1) = 'T'
        AND SAFE_CAST(SUBSTR(icd_code, 2, 2) AS INT64) IS NOT NULL
        AND SAFE_CAST(SUBSTR(icd_code, 2, 2) AS INT64) BETWEEN 0 AND 98
      )
    )
),

multi_trauma_admissions AS (
  SELECT
    di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN injury_codes ic
    ON di.icd_code = ic.icd_code
  GROUP BY di.hadm_id
  HAVING COUNT(DISTINCT di.icd_code) >= 2
),

-- Medication count in first 7 days
medication_complexity AS (
  SELECT
    pa.subject_id,
    pa.hadm_id,
    pa.admittime,
    pa.dischtime,
    pa.hospital_expire_flag,
    pa.deathtime,
    COUNT(DISTINCT pr.drug) AS med_count
  FROM patient_admissions pa
  INNER JOIN multi_trauma_admissions mta
    ON pa.hadm_id = mta.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.prescriptions pr
    ON pa.hadm_id = pr.hadm_id
    AND pr.starttime >= pa.admittime
    AND pr.starttime <= DATETIME_ADD(pa.admittime, INTERVAL 7 DAY)
  GROUP BY pa.subject_id, pa.hadm_id, pa.admittime, pa.dischtime, pa.hospital_expire_flag, pa.deathtime
),

-- Assign tertiles
tertiles AS (
  SELECT
    *,
    NTILE(3) OVER (ORDER BY med_count) AS complexity_tertile
  FROM medication_complexity
),

-- Compute readmissions using JOIN instead of correlated subquery
readmissions AS (
  SELECT
    t.*,
    -- Flag 30-day readmission
    CASE
      WHEN a_next.hadm_id IS NOT NULL THEN 1
      ELSE 0
    END AS thirty_day_readmit
  FROM tertiles t
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a_next
    ON t.subject_id = a_next.subject_id
    AND a_next.admittime > t.dischtime
    AND a_next.admittime <= DATETIME_ADD(t.dischtime, INTERVAL 30 DAY)
),

-- Final aggregation by tertile
summary AS (
  SELECT
    complexity_tertile,
    COUNT(*) AS admissions,
    AVG(med_count) AS mean_med_count,
    MIN(med_count) AS min_med_count,
    MAX(med_count) AS max_med_count,
    AVG(TIMESTAMP_DIFF(dischtime, admittime, DAY)) AS mean_los_days,
    AVG(hospital_expire_flag) * 100 AS mortality_pct,
    AVG(thirty_day_readmit) * 100 AS thirty_day_readmission_pct
  FROM readmissions
  GROUP BY complexity_tertile
)

SELECT
  complexity_tertile,
  admissions,
  ROUND(mean_med_count, 2) AS mean_med_count,
  min_med_count,
  max_med_count,
  ROUND(mean_los_days, 2) AS mean_los_days,
  ROUND(mortality_pct, 2) AS mortality_pct,
  ROUND(thirty_day_readmission_pct, 2) AS thirty_day_readmission_pct
FROM summary
ORDER BY complexity_tertile;