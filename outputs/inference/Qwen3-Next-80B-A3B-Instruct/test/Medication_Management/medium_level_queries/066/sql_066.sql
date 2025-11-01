WITH target_admissions AS (
  SELECT DISTINCT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 58 AND 68
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 72
    AND a.dischtime IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
        ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND (
          d_icd.long_title ILIKE '%diabetes mellitus type 2%'
          OR d_icd.long_title ILIKE '%type 2 diabetes%'
          OR d_icd.long_title ILIKE '%t2dm%'
        )
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
        ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND d_icd.long_title ILIKE '%heart failure%'
    )
),
glp1_prescriptions AS (
  SELECT
    p.hadm_id,
    p.starttime,
    CASE
      WHEN LOWER(p.drug) LIKE '%exenatide%'
        OR LOWER(p.drug) LIKE '%liraglutide%'
        OR LOWER(p.drug) LIKE '%semaglutide%'
        OR LOWER(p.drug) LIKE '%dulaglutide%'
        OR LOWER(p.drug) LIKE '%lixisenatide%'
        OR LOWER(p.drug) LIKE '%albiglutide%'
        OR LOWER(p.drug) LIKE '%exenatide extended-release%'
        OR LOWER(p.drug) LIKE '%liraglutide injection%'
        OR LOWER(p.drug) LIKE '%semaglutide injection%'
        OR LOWER(p.drug) LIKE '%dulaglutide injection%'
        OR LOWER(p.drug) LIKE '%lixisenatide injection%'
      THEN 1
      ELSE 0
    END AS is_glp1
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  WHERE p.starttime IS NOT NULL
    AND p.hadm_id IN (SELECT hadm_id FROM target_admissions)
),
glp1_flags AS (
  SELECT
    ta.hadm_id,
    MAX(CASE
      WHEN gp.starttime BETWEEN ta.admittime AND TIMESTAMP_ADD(ta.admittime, INTERVAL 72 HOUR)
      THEN 1 ELSE 0
    END) AS glp1_first_72h,
    MAX(CASE
      WHEN gp.starttime BETWEEN TIMESTAMP_SUB(ta.dischtime, INTERVAL 12 HOUR) AND ta.dischtime
      THEN 1 ELSE 0
    END) AS glp1_final_12h
  FROM target_admissions ta
  LEFT JOIN glp1_prescriptions gp ON ta.hadm_id = gp.hadm_id
  GROUP BY ta.hadm_id
)
SELECT
  ROUND(100.0 * SUM(glp1_first_72h) / COUNT(*), 2) AS pct_glp1_first_72h,
  ROUND(100.0 * SUM(glp1_final_12h) / COUNT(*), 2) AS pct_glp1_final_12h,
  ROUND(100.0 * (SUM(glp1_final_12h) - SUM(glp1_first_72h)) / COUNT(*), 2) AS abs_diff_pp
FROM glp1_flags;