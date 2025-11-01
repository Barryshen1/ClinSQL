WITH population AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 45 AND 55
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 10 AND d.icd_code LIKE 'E11%')
          OR (d.icd_version = 9 AND d.icd_code LIKE '250%' AND LENGTH(d.icd_code) = 5 AND SUBSTR(d.icd_code, 5, 1) IN ('0', '1'))
        )
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
          OR (d.icd_version = 9 AND d.icd_code LIKE '428%')
        )
    )
),

glp1_stats AS (
  SELECT
    p.hadm_id,
    MAX(CASE WHEN 
          pr.starttime >= p.admittime 
          AND pr.starttime <= p.admittime + INTERVAL '72' HOUR 
        THEN 1 ELSE 0 END) AS started_within_72h,
    MAX(CASE WHEN 
          pr.starttime < p.dischtime 
          AND (pr.stoptime IS NULL OR pr.stoptime > p.dischtime - INTERVAL '48' HOUR)
        THEN 1 ELSE 0 END) AS on_in_last_48h
  FROM population p
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON p.hadm_id = pr.hadm_id
    AND (
      LOWER(pr.drug) LIKE '%exenatide%' OR
      LOWER(pr.drug) LIKE '%liraglutide%' OR
      LOWER(pr.drug) LIKE '%semaglutide%' OR
      LOWER(pr.drug) LIKE '%dulaglutide%' OR
      LOWER(pr.drug) LIKE '%lixisenatide%'
    )
  GROUP BY p.hadm_id
)

SELECT
  (SUM(started_within_72h) * 100.0 / COUNT(*)) AS pct_started_within_72h,
  (SUM(on_in_last_48h) * 100.0 / COUNT(*)) AS pct_on_in_last_48h,
  (SUM(on_in_last_48h) * 100.0 / COUNT(*)) - (SUM(started_within_72h) * 100.0 / COUNT(*)) AS net_change
FROM glp1_stats;