WITH cohort AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 48
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
       AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND d.icd_version = 10
        AND LOWER(dd.long_title) LIKE '%diabetes mellitus, type 2%'
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
       AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND d.icd_version = 10
        AND LOWER(dd.long_title) LIKE '%heart failure%'
    )
),
med_flags AS (
  SELECT
    c.hadm_id,
    -- first 48h
    MAX(IF(
      LOWER(p.drug) LIKE '%insulin%' 
      AND p.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR),
      1, 0
    )) AS insulin_48h,
    MAX(IF(
      LOWER(p.drug) NOT LIKE '%insulin%'
      AND LOWER(p.route) LIKE '%oral%'
      AND p.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR),
      1, 0
    )) AS oral_48h,
    -- final 24h
    MAX(IF(
      LOWER(p.drug) LIKE '%insulin%'
      AND p.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 24 HOUR) AND c.dischtime,
      1, 0
    )) AS insulin_24h,
    MAX(IF(
      LOWER(p.drug) NOT LIKE '%insulin%'
      AND LOWER(p.route) LIKE '%oral%'
      AND p.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 24 HOUR) AND c.dischtime,
      1, 0
    )) AS oral_24h
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON p.hadm_id = c.hadm_id
  GROUP BY c.hadm_id
),
denominator AS (
  SELECT COUNT(*) AS N
  FROM cohort
)
SELECT
  ANY_VALUE(d.N) AS N,
  -- first 48h
  ROUND(100.0 * SUM(m.insulin_48h) / ANY_VALUE(d.N), 2)       AS pct_insulin_first_48h,
  ROUND(100.0 * SUM(m.oral_48h)   / ANY_VALUE(d.N), 2)       AS pct_oral_first_48h,
  -- final 24h
  ROUND(100.0 * SUM(m.insulin_24h) / ANY_VALUE(d.N), 2)      AS pct_insulin_final_24h,
  ROUND(100.0 * SUM(m.oral_24h)    / ANY_VALUE(d.N), 2)      AS pct_oral_final_24h
FROM med_flags m
CROSS JOIN denominator d;