WITH pneumo_adm AS (
  -- 1. Female patients age 76-86 with pneumonia
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
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
      ON d.icd_code = dicd.icd_code
      AND d.icd_version = dicd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 76 AND 86
    AND LOWER(dicd.long_title) LIKE '%pneumonia%'
  GROUP BY
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
),

med_count AS (
  -- 2. Count distinct drugs per admission in first 7 days
  SELECT
    p.hadm_id,
    COUNT(DISTINCT TRIM(drug)) AS med_score
  FROM
    pneumo_adm p
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
      ON p.hadm_id = pr.hadm_id
      AND pr.starttime BETWEEN p.admittime
        AND TIMESTAMP_ADD(p.admittime, INTERVAL 7 DAY)
  GROUP BY
    p.hadm_id
),

adm_with_scores AS (
  -- 3. Bring together scores and compute LOS and readmit flag
  SELECT
    p.subject_id,
    p.hadm_id,
    p.admittime,
    p.dischtime,
    COALESCE(m.med_score, 0) AS med_score,
    -- length of stay in days
    TIMESTAMP_DIFF(p.dischtime, p.admittime, DAY) AS los_days,
    p.hospital_expire_flag,
    -- 30-day readmission flag
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE a2.subject_id = p.subject_id
          AND a2.admittime > p.dischtime
          AND a2.admittime <= TIMESTAMP_ADD(p.dischtime, INTERVAL 30 DAY)
      ) THEN 1
      ELSE 0
    END AS readmit30_flag
  FROM
    pneumo_adm p
    LEFT JOIN med_count m
      ON p.hadm_id = m.hadm_id
),

scored_with_tertile AS (
  -- 4. Assign tertile by med_score
  SELECT
    *,
    NTILE(3) OVER (ORDER BY med_score) AS tertile
  FROM
    adm_with_scores
)

-- 5. Aggregate per tertile
SELECT
  tertile,
  COUNT(*) AS admission_count,
  MIN(med_score) AS min_med_score,
  AVG(med_score) AS avg_med_score,
  MAX(med_score) AS max_med_score,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(100.0 * AVG(hospital_expire_flag), 2) AS pct_in_hospital_mortality,
  ROUND(100.0 * AVG(readmit30_flag), 2) AS pct_30_day_readmission
FROM
  scored_with_tertile
GROUP BY
  tertile
ORDER BY
  tertile;