WITH cohort AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE 
    p.anchor_age BETWEEN 48 AND 58
    AND p.gender = 'F'
    AND a.dischtime IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE 
        d.subject_id = p.subject_id 
        AND d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '250%')
          OR (d.icd_version = 10 AND (
            d.icd_code LIKE 'E10%' OR 
            d.icd_code LIKE 'E11%' OR 
            d.icd_code LIKE 'E12%' OR 
            d.icd_code LIKE 'E13%' OR 
            d.icd_code LIKE 'E14%'
          ))
        )
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE 
        d.subject_id = p.subject_id 
        AND d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '428%')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
        )
    )
),

glp1_prescriptions AS (
  SELECT 
    subject_id, 
    hadm_id, 
    starttime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE 
    (LOWER(drug) LIKE '%liraglutide%' OR 
     LOWER(drug) LIKE '%victoza%' OR 
     LOWER(drug) LIKE '%semaglutide%' OR 
     LOWER(drug) LIKE '%ozempic%' OR 
     LOWER(drug) LIKE '%exenatide%' OR 
     LOWER(drug) LIKE '%byetta%' OR 
     LOWER(drug) LIKE '%bydureon%' OR 
     LOWER(drug) LIKE '%dulaglutide%' OR 
     LOWER(drug) LIKE '%trulicity%' OR 
     LOWER(drug) LIKE '%lixisenatide%' OR 
     LOWER(drug) LIKE '%adlyxin%')
    AND LOWER(route) LIKE '%subcut%'
)

SELECT
  COUNTIF(first_24h) * 100.0 / COUNT(*) AS first_24h_prevalence,
  COUNTIF(final_12h) * 100.0 / COUNT(*) AS final_12h_prevalence
FROM (
  SELECT
    c.subject_id,
    MAX(gp.starttime BETWEEN c.admittime AND c.admittime + INTERVAL '24' HOUR) AS first_24h,
    MAX(gp.starttime BETWEEN c.dischtime - INTERVAL '12' HOUR AND c.dischtime) AS final_12h
  FROM cohort c
  LEFT JOIN glp1_prescriptions gp 
    ON c.subject_id = gp.subject_id AND c.hadm_id = gp.hadm_id
  GROUP BY c.subject_id
) AS patient_flags;