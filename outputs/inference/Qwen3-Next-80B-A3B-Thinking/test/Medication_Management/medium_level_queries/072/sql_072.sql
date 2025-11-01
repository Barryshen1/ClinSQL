WITH cohort AS (
  SELECT 
    a.hadm_id, 
    a.admittime, 
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 79 AND 89
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1
      WHERE d1.hadm_id = a.hadm_id
        AND (d1.icd_code LIKE 'E11%' OR (d1.icd_code LIKE '250%' AND d1.icd_version = 9))
    )
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
      WHERE d2.hadm_id = a.hadm_id
        AND (d2.icd_code LIKE 'I50%' OR (d2.icd_code LIKE '428%' AND d2.icd_version = 9))
    )
)

SELECT
  AVG(CASE WHEN EXISTS (
    SELECT 1 
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    WHERE p.hadm_id = c.hadm_id
      AND p.starttime BETWEEN c.admittime AND c.admittime + INTERVAL '12' HOUR
      AND (
        LOWER(p.drug) LIKE '%liraglutide%' OR
        LOWER(p.drug) LIKE '%victoza%' OR
        LOWER(p.drug) LIKE '%semaglutide%' OR
        LOWER(p.drug) LIKE '%ozempic%' OR
        LOWER(p.drug) LIKE '%rybelsus%' OR
        LOWER(p.drug) LIKE '%exenatide%' OR
        LOWER(p.drug) LIKE '%byetta%' OR
        LOWER(p.drug) LIKE '%bydureon%' OR
        LOWER(p.drug) LIKE '%dulaglutide%' OR
        LOWER(p.drug) LIKE '%trulicity%' OR
        LOWER(p.drug) LIKE '%albiglutide%' OR
        LOWER(p.drug) LIKE '%lucerent%' OR
        LOWER(p.drug) LIKE '%lixisenatide%' OR
        LOWER(p.drug) LIKE '%adlyxin%'
      )
  ) THEN 1 ELSE 0 END) * 100 AS first12h_percent,
  AVG(CASE WHEN EXISTS (
    SELECT 1 
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    WHERE p.hadm_id = c.hadm_id
      AND p.starttime BETWEEN c.dischtime - INTERVAL '24' HOUR AND c.dischtime
      AND (
        LOWER(p.drug) LIKE '%liraglutide%' OR
        LOWER(p.drug) LIKE '%victoza%' OR
        LOWER(p.drug) LIKE '%semaglutide%' OR
        LOWER(p.drug) LIKE '%ozempic%' OR
        LOWER(p.drug) LIKE '%rybelsus%' OR
        LOWER(p.drug) LIKE '%exenatide%' OR
        LOWER(p.drug) LIKE '%byetta%' OR
        LOWER(p.drug) LIKE '%bydureon%' OR
        LOWER(p.drug) LIKE '%dulaglutide%' OR
        LOWER(p.drug) LIKE '%trulicity%' OR
        LOWER(p.drug) LIKE '%albiglutide%' OR
        LOWER(p.drug) LIKE '%lucerent%' OR
        LOWER(p.drug) LIKE '%lixisenatide%' OR
        LOWER(p.drug) LIKE '%adlyxin%'
      )
  ) THEN 1 ELSE 0 END) * 100 AS last24h_percent,
  (AVG(CASE WHEN EXISTS (
    SELECT 1 
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    WHERE p.hadm_id = c.hadm_id
      AND p.starttime BETWEEN c.dischtime - INTERVAL '24' HOUR AND c.dischtime
      AND (
        LOWER(p.drug) LIKE '%liraglutide%' OR
        LOWER(p.drug) LIKE '%victoza%' OR
        LOWER(p.drug) LIKE '%semaglutide%' OR
        LOWER(p.drug) LIKE '%ozempic%' OR
        LOWER(p.drug) LIKE '%rybelsus%' OR
        LOWER(p.drug) LIKE '%exenatide%' OR
        LOWER(p.drug) LIKE '%byetta%' OR
        LOWER(p.drug) LIKE '%bydureon%' OR
        LOWER(p.drug) LIKE '%dulaglutide%' OR
        LOWER(p.drug) LIKE '%trulicity%' OR
        LOWER(p.drug) LIKE '%albiglutide%' OR
        LOWER(p.drug) LIKE '%lucerent%' OR
        LOWER(p.drug) LIKE '%lixisenatide%' OR
        LOWER(p.drug) LIKE '%adlyxin%'
      )
  ) THEN 1 ELSE 0 END) - 
   AVG(CASE WHEN EXISTS (
    SELECT 1 
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    WHERE p.hadm_id = c.hadm_id
      AND p.starttime BETWEEN c.admittime AND c.admittime + INTERVAL '12' HOUR
      AND (
        LOWER(p.drug) LIKE '%liraglutide%' OR
        LOWER(p.drug) LIKE '%victoza%' OR
        LOWER(p.drug) LIKE '%semaglutide%' OR
        LOWER(p.drug) LIKE '%ozempic%' OR
        LOWER(p.drug) LIKE '%rybelsus%' OR
        LOWER(p.drug) LIKE '%exenatide%' OR
        LOWER(p.drug) LIKE '%byetta%' OR
        LOWER(p.drug) LIKE '%bydureon%' OR
        LOWER(p.drug) LIKE '%dulaglutide%' OR
        LOWER(p.drug) LIKE '%trulicity%' OR
        LOWER(p.drug) LIKE '%albiglutide%' OR
        LOWER(p.drug) LIKE '%lucerent%' OR
        LOWER(p.drug) LIKE '%lixisenatide%' OR
        LOWER(p.drug) LIKE '%adlyxin%'
      )
  ) THEN 1 ELSE 0 END)) * 100 AS net_change
FROM cohort c;