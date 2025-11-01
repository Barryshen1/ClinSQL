WITH cohort AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 48 AND 58
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '250%')
          OR (d.icd_version = 10 AND (d.icd_code LIKE 'E08%' OR d.icd_code LIKE 'E09%' OR d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E13%'))
        )
    )
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '428%')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
        )
    )
),
glp1_admin AS (
  SELECT 
    e.hadm_id,
    e.charttime
  FROM `physionet-data.mimiciv_3_1_hosp.emar` e
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` ed
    ON e.emar_id = ed.emar_id
  WHERE 
    (LOWER(e.medication) LIKE '%exenatide%' 
     OR LOWER(e.medication) LIKE '%liraglutide%' 
     OR LOWER(e.medication) LIKE '%dulaglutide%' 
     OR LOWER(e.medication) LIKE '%semaglutide%'
     OR LOWER(e.medication) LIKE '%lixisenatide%'
     OR LOWER(e.medication) LIKE '%albiglutide%')
    AND LOWER(ed.route) LIKE '%subcut%'
    AND ed.administration_type = 'Administered'
),
flags AS (
  SELECT 
    c.hadm_id,
    MAX(CASE WHEN g.charttime <= c.admittime + INTERVAL '24' HOUR THEN 1 ELSE 0 END) AS first_24h_flag,
    MAX(CASE WHEN g.charttime >= c.dischtime - INTERVAL '12' HOUR AND g.charttime <= c.dischtime THEN 1 ELSE 0 END) AS final_12h_flag
  FROM cohort c
  LEFT JOIN glp1_admin g
    ON c.hadm_id = g.hadm_id
  GROUP BY c.hadm_id
)
SELECT
  COUNT(*) AS total_admissions,
  SUM(first_24h_flag) AS count_first_24h,
  SUM(final_12h_flag) AS count_final_12h,
  ROUND(SUM(first_24h_flag) * 100.0 / COUNT(*), 2) AS pct_first_24h,
  ROUND(SUM(final_12h_flag) * 100.0 / COUNT(*), 2) AS pct_final_12h
FROM flags;