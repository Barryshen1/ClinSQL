WITH cohort AS (
    SELECT a.hadm_id, a.admittime, a.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
    WHERE p.gender = 'M'
      AND p.anchor_age BETWEEN 53 AND 63
      AND EXISTS (
          SELECT 1
          FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
          WHERE d.hadm_id = a.hadm_id
            AND (
                (d.icd_version = 9 AND d.icd_code LIKE '250%')
                OR (d.icd_version = 10 AND (d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E12%' OR d.icd_code LIKE 'E13%' OR d.icd_code LIKE 'E14%'))
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
glp1_prescriptions AS (
    SELECT c.hadm_id,
           MAX(CASE WHEN p.starttime >= c.admittime AND p.starttime <= c.admittime + INTERVAL 24 HOUR THEN 1 ELSE 0 END) AS first_24h,
           MAX(CASE WHEN p.starttime >= c.dischtime - INTERVAL 12 HOUR AND p.starttime <= c.dischtime THEN 1 ELSE 0 END) AS last_12h
    FROM cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON c.hadm_id = p.hadm_id
        AND (LOWER(p.drug) LIKE '%exenatide%' OR LOWER(p.drug) LIKE '%liraglutide%' OR LOWER(p.drug) LIKE '%semaglutide%' OR LOWER(p.drug) LIKE '%dulaglutide%' OR LOWER(p.drug) LIKE '%albiglutide%' OR LOWER(p.drug) LIKE '%lixisenatide%')
        AND (LOWER(p.route) LIKE '%subcutaneous%' OR LOWER(p.route) IN ('sc', 'sq'))
    GROUP BY c.hadm_id
)
SELECT 
    AVG(first_24h) * 100 AS percent_first_24h,
    AVG(last_12h) * 100 AS percent_last_12h
FROM glp1_prescriptions;