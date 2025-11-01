WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
),
dx AS (
  SELECT
    ci.subject_id,
    ci.hadm_id,
    MAX(CASE WHEN (d.icd_version = 9 AND ci.icd_code LIKE '250%') 
                  OR (d.icd_version = 10 AND ci.icd_code LIKE 'E11%') 
             THEN 1 ELSE 0 END) AS has_t2d,
    MAX(CASE WHEN (d.icd_version = 9 AND ci.icd_code LIKE '428%') 
                  OR (d.icd_version = 10 AND ci.icd_code LIKE 'I50%') 
             THEN 1 ELSE 0 END) AS has_hf
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` ci
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
      ON ci.icd_code = d.icd_code
     AND ci.icd_version = d.icd_version
  GROUP BY
    ci.subject_id,
    ci.hadm_id
),
cohort_dx AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime
  FROM
    cohort c
    JOIN dx
      ON c.subject_id = dx.subject_id
     AND c.hadm_id = dx.hadm_id
  WHERE
    dx.has_t2d = 1
    AND dx.has_hf = 1
),
med_flags AS (
  SELECT
    cd.subject_id,
    cd.hadm_id,
    -- Flag any insulin start in first 72h
    MAX(CASE 
          WHEN LOWER(p.drug) LIKE '%insulin%' 
           AND p.starttime < TIMESTAMP_ADD(cd.admittime, INTERVAL 72 HOUR)
          THEN 1 ELSE 0 END) AS insulin_first72,
    -- Flag any oral agent (non‐insulin) start in first 72h
    MAX(CASE 
          WHEN LOWER(p.drug) NOT LIKE '%insulin%' 
           AND p.starttime < TIMESTAMP_ADD(cd.admittime, INTERVAL 72 HOUR)
          THEN 1 ELSE 0 END) AS oral_first72,
    -- Flag any insulin start in final 72h
    MAX(CASE 
          WHEN LOWER(p.drug) LIKE '%insulin%' 
           AND p.stoptime  > TIMESTAMP_SUB(cd.dischtime, INTERVAL 72 HOUR)
          THEN 1 ELSE 0 END) AS insulin_last72,
    -- Flag any oral agent (non‐insulin) start in final 72h
    MAX(CASE 
          WHEN LOWER(p.drug) NOT LIKE '%insulin%' 
           AND p.stoptime  > TIMESTAMP_SUB(cd.dischtime, INTERVAL 72 HOUR)
          THEN 1 ELSE 0 END) AS oral_last72
  FROM
    cohort_dx cd
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
      ON cd.subject_id = p.subject_id
     AND cd.hadm_id    = p.hadm_id
  GROUP BY
    cd.subject_id,
    cd.hadm_id
)
SELECT
  -- First 72h
  ROUND(100.0 * SUM(insulin_first72) / COUNT(*), 1) AS pct_insulin_first72,
  ROUND(100.0 * SUM(oral_first72)    / COUNT(*), 1) AS pct_oral_first72,
  -- Final 72h
  ROUND(100.0 * SUM(insulin_last72)  / COUNT(*), 1) AS pct_insulin_last72,
  ROUND(100.0 * SUM(oral_last72)     / COUNT(*), 1) AS pct_oral_last72
FROM
  med_flags;