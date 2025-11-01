WITH cohort AS (
  SELECT 
    a.hadm_id, 
    a.admittime, 
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 57 AND 67
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      WHERE d.hadm_id = a.hadm_id 
        AND (
          d.icd_code LIKE 'E10%' OR 
          d.icd_code LIKE 'E11%' OR 
          d.icd_code LIKE 'E12%' OR 
          d.icd_code LIKE 'E13%' OR 
          d.icd_code LIKE 'E14%'
        )
    )
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      WHERE d.hadm_id = a.hadm_id 
        AND d.icd_code LIKE 'I50%'
    )
)

SELECT 
  first_48h_pct,
  last_12h_pct,
  last_12h_pct - first_48h_pct AS abs_change,
  CASE 
    WHEN first_48h_pct = 0 THEN NULL 
    ELSE (last_12h_pct - first_48h_pct) / first_48h_pct * 100 
  END AS rel_change
FROM (
  SELECT 
    COUNTIF(first_48h) * 100.0 / COUNT(*) AS first_48h_pct,
    COUNTIF(last_12h) * 100.0 / COUNT(*) AS last_12h_pct
  FROM (
    SELECT 
      c.hadm_id,
      EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
        WHERE 
          p.hadm_id = c.hadm_id
          AND p.starttime BETWEEN c.admittime AND c.admittime + INTERVAL '48' HOUR
          AND (
            LOWER(p.drug) LIKE '%liraglutide%' OR
            LOWER(p.drug) LIKE '%semaglutide%' OR
            LOWER(p.drug) LIKE '%exenatide%' OR
            LOWER(p.drug) LIKE '%dulaglutide%' OR
            LOWER(p.drug) LIKE '%lixisenatide%' OR
            LOWER(p.drug) LIKE '%albiglutide%' OR
            LOWER(p.drug) LIKE '%tirzepatide%'
          )
      ) AS first_48h,
      EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
        WHERE 
          p.hadm_id = c.hadm_id
          AND p.starttime BETWEEN c.dischtime - INTERVAL '12' HOUR AND c.dischtime
          AND (
            LOWER(p.drug) LIKE '%liraglutide%' OR
            LOWER(p.drug) LIKE '%semaglutide%' OR
            LOWER(p.drug) LIKE '%exenatide%' OR
            LOWER(p.drug) LIKE '%dulaglutide%' OR
            LOWER(p.drug) LIKE '%lixisenatide%' OR
            LOWER(p.drug) LIKE '%albiglutide%' OR
            LOWER(p.drug) LIKE '%tirzepatide%'
          )
      ) AS last_12h
    FROM cohort c
  ) AS subquery
);