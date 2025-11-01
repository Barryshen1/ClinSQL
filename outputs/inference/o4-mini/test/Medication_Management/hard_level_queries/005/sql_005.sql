WITH hepatic_adm AS (
  -- 1. Filter admissions of M patients age 43-53 with hepatic failure
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
    AND EXISTS (
      -- has a hepatic failure diagnosis
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
        ON d.icd_code = dicd.icd_code
        AND d.icd_version = dicd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND LOWER(dicd.long_title) LIKE '%hepatic failure%'
    )
),
med_complexity AS (
  -- 2. Compute medication complexity over first 72h
  SELECT
    ha.hadm_id,
    COUNT(DISTINCT pr.drug) AS complexity_score
  FROM
    hepatic_adm AS ha
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    ON pr.hadm_id = ha.hadm_id
     AND pr.starttime BETWEEN ha.admittime
                         AND TIMESTAMP_ADD(ha.admittime, INTERVAL 72 HOUR)
  GROUP BY
    ha.hadm_id
),
readmit_flags AS (
  -- 3. Compute 30-day readmission flag per admission
  SELECT
    ha.*,
    mc.complexity_score,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a2
        WHERE a2.subject_id = ha.subject_id
          AND a2.admittime > ha.dischtime
          AND a2.admittime <= TIMESTAMP_ADD(ha.dischtime, INTERVAL 30 DAY)
      ) THEN 1
      ELSE 0
    END AS readmit30d_flag
  FROM
    hepatic_adm AS ha
  LEFT JOIN
    med_complexity AS mc
    ON ha.hadm_id = mc.hadm_id
),
quintiled AS (
  -- 4. Assign quintiles by complexity_score
  SELECT
    *,
    NTILE(5) OVER (ORDER BY complexity_score) AS quintile
  FROM
    readmit_flags
)
-- 5. Aggregate per quintile
SELECT
  quintile,
  COUNT(1) AS n_admissions,
  MIN(complexity_score) AS min_score,
  MAX(complexity_score) AS max_score,
  ROUND(AVG(complexity_score), 2) AS mean_score,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(100 * AVG(hospital_expire_flag), 1) AS pct_in_hosp_mortality,
  ROUND(100 * AVG(readmit30d_flag), 1) AS pct_30d_readmit
FROM
  quintiled
GROUP BY
  quintile
ORDER BY
  quintile;