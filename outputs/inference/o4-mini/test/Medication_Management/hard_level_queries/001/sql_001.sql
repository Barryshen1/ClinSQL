WITH cohort AS (
  SELECT
    a1.subject_id,
    a1.hadm_id,
    a1.admittime,
    a1.dischtime,
    a1.hospital_expire_flag,
    TIMESTAMP_DIFF(a1.dischtime, a1.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a1
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a1.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1
      ON a1.subject_id = d1.subject_id
     AND a1.hadm_id = d1.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
      ON d1.icd_code = dicd.icd_code
     AND d1.icd_version = dicd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 76 AND 86
    AND LOWER(dicd.long_title) LIKE '%cardiac arrest%'
),
med_score AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    c.los_days,
    COUNT(DISTINCT pr.drug) AS complexity_score
  FROM
    cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
      ON c.subject_id = pr.subject_id
     AND c.hadm_id = pr.hadm_id
     AND pr.drug IS NOT NULL
     AND pr.starttime BETWEEN c.admittime
                        AND TIMESTAMP_ADD(c.admittime, INTERVAL 7 DAY)
  GROUP BY
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    c.los_days
),
readmit AS (
  SELECT
    m.*,
    CASE WHEN COUNT(a2.hadm_id) > 0 THEN 1 ELSE 0 END AS readmit30_flag
  FROM
    med_score m
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a2
      ON m.subject_id = a2.subject_id
     AND a2.admittime > m.dischtime
     AND a2.admittime <= TIMESTAMP_ADD(m.dischtime, INTERVAL 30 DAY)
  GROUP BY
    m.subject_id,
    m.hadm_id,
    m.admittime,
    m.dischtime,
    m.hospital_expire_flag,
    m.los_days,
    m.complexity_score
),
quintiles AS (
  SELECT
    r.*,
    NTILE(5) OVER (ORDER BY r.complexity_score) AS complexity_quintile
  FROM
    readmit r
)
SELECT
  complexity_quintile,
  COUNT(*) AS patient_count,
  ROUND(AVG(complexity_score),2) AS avg_score,
  MIN(complexity_score) AS min_score,
  MAX(complexity_score) AS max_score,
  ROUND(AVG(los_days),2) AS avg_los_days,
  ROUND(100 * AVG(hospital_expire_flag),2) AS mortality_pct,
  ROUND(100 * AVG(readmit30_flag),2) AS readmission30_pct
FROM
  quintiles
GROUP BY
  complexity_quintile
ORDER BY
  complexity_quintile;