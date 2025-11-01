WITH copd_admissions AS (
  -- Identify admissions for male patients age 58-68 with COPD exacerbation
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 58 AND 68
    AND (
      -- ICD-10: J44.1, J44.0, J44.9; ICD-9: 491.21, 491.22, 491.20, 496
      (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^J44'))
      OR (d.icd_version = 9 AND d.icd_code IN ('49121', '49122', '49120', '496'))
    )
),

first_admissions AS (
  -- Only keep the first qualifying admission per patient
  SELECT
    subject_id,
    MIN(admittime) AS first_admittime
  FROM copd_admissions
  GROUP BY subject_id
),

index_admissions AS (
  -- Index admissions: join back to get hadm_id etc.
  SELECT
    ca.*
  FROM copd_admissions ca
  JOIN first_admissions fa
    ON ca.subject_id = fa.subject_id AND ca.admittime = fa.first_admittime
),

med_complexity AS (
  -- For each index admission, count unique medications ordered in first 72h
  SELECT
    ia.subject_id,
    ia.hadm_id,
    ia.admittime,
    ia.dischtime,
    ia.hospital_expire_flag,
    TIMESTAMP_DIFF(ia.dischtime, ia.admittime, SECOND)/86400.0 AS los_days,
    COUNT(DISTINCT pr.drug) AS complexity_score
  FROM
    index_admissions ia
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
      ON ia.hadm_id = pr.hadm_id
      AND pr.starttime >= ia.admittime
      AND pr.starttime < TIMESTAMP_ADD(ia.admittime, INTERVAL 72 HOUR)
  GROUP BY
    ia.subject_id, ia.hadm_id, ia.admittime, ia.dischtime, ia.hospital_expire_flag
),

tertile_assign AS (
  -- Assign tertiles by complexity score
  SELECT
    *,
    NTILE(3) OVER (ORDER BY complexity_score) AS tertile
  FROM med_complexity
),

readmissions AS (
  -- For each index admission, check for readmission within 30 days
  SELECT
    ia.subject_id,
    ia.hadm_id,
    ia.dischtime,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE a2.subject_id = ia.subject_id
          AND a2.admittime > ia.dischtime
          AND a2.admittime <= TIMESTAMP_ADD(ia.dischtime, INTERVAL 30 DAY)
      ) THEN 1
      ELSE 0
    END AS readmit_30d
  FROM
    index_admissions ia
)

SELECT
  t.tertile,
  COUNT(*) AS n,
  MIN(t.complexity_score) AS min_complexity,
  MAX(t.complexity_score) AS max_complexity,
  AVG(t.complexity_score) AS mean_complexity,
  AVG(t.los_days) AS mean_los_days,
  100.0 * AVG(CASE WHEN t.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality_percent,
  100.0 * AVG(r.readmit_30d) AS readmit_30d_percent
FROM
  tertile_assign t
  LEFT JOIN readmissions r
    ON t.subject_id = r.subject_id AND t.hadm_id = r.hadm_id
GROUP BY
  t.tertile
ORDER BY
  t.tertile;