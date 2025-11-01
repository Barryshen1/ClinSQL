WITH copd_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    -- Compute LOS in days
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
   AND d.icd_version = dd.icd_version
  WHERE p.gender = 'Male'
    AND p.anchor_age BETWEEN 58 AND 68
    AND LOWER(dd.long_title) LIKE '%copd%'
),
complexity AS (
  SELECT
    ca.subject_id,
    ca.hadm_id,
    COUNT(DISTINCT pr.drug) AS complexity_score
  FROM copd_admissions ca
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON ca.subject_id = pr.subject_id
    AND ca.hadm_id = pr.hadm_id
    AND pr.starttime >= ca.admittime
    AND pr.starttime < TIMESTAMP_ADD(ca.admittime, INTERVAL 72 HOUR)
  GROUP BY ca.subject_id, ca.hadm_id
),
readmissions AS (
  SELECT
    ca.subject_id,
    ca.hadm_id,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE a2.subject_id = ca.subject_id
          AND a2.hadm_id != ca.hadm_id
          AND a2.admittime > ca.dischtime
          AND a2.admittime <= TIMESTAMP_ADD(ca.dischtime, INTERVAL 30 DAY)
      ) THEN 1 ELSE 0
    END AS readmit_30d_flag
  FROM copd_admissions ca
),
full_data AS (
  SELECT
    ca.subject_id,
    ca.hadm_id,
    co.complexity_score,
    ca.los_days,
    ca.hospital_expire_flag,
    ra.readmit_30d_flag
  FROM copd_admissions ca
  JOIN complexity co
    ON ca.subject_id = co.subject_id
   AND ca.hadm_id = co.hadm_id
  JOIN readmissions ra
    ON ca.subject_id = ra.subject_id
   AND ca.hadm_id = ra.hadm_id
),
tertiles AS (
  SELECT
    *,
    NTILE(3) OVER (ORDER BY complexity_score) AS tertile
  FROM full_data
)
SELECT
  tertile,
  COUNT(*) AS n,
  MIN(complexity_score) AS min_complexity,
  MAX(complexity_score) AS max_complexity,
  ROUND(AVG(complexity_score), 2) AS mean_complexity,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(100 * AVG(hospital_expire_flag), 2) AS mortality_percent,
  ROUND(100 * AVG(readmit_30d_flag), 2) AS readmit_30d_percent
FROM tertiles
GROUP BY tertile
ORDER BY tertile;