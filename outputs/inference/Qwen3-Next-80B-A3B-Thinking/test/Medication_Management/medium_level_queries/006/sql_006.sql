WITH cohort AS (
    SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
    WHERE p.anchor_age BETWEEN 48 AND 58
      AND EXISTS (
          SELECT 1
          FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
          WHERE d.hadm_id = a.hadm_id
            AND d.icd_code LIKE 'E11%'
      )
      AND EXISTS (
          SELECT 1
          FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
          WHERE d.hadm_id = a.hadm_id
            AND d.icd_code LIKE 'I50%'
      )
),
glp1_prescriptions AS (
    SELECT c.hadm_id,
           MAX(CASE WHEN p.starttime BETWEEN c.admittime AND c.admittime + INTERVAL 72 HOUR THEN 1 ELSE 0 END) AS first_72h,
           MAX(CASE WHEN p.starttime BETWEEN c.dischtime - INTERVAL 48 HOUR AND c.dischtime THEN 1 ELSE 0 END) AS last_48h
    FROM cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
        ON c.hadm_id = p.hadm_id
        AND p.route = 'subcutaneous'
        AND (LOWER(p.drug) LIKE '%liraglutide%'
             OR LOWER(p.drug) LIKE '%semaglutide%'
             OR LOWER(p.drug) LIKE '%exenatide%'
             OR LOWER(p.drug) LIKE '%dulaglutide%'
             OR LOWER(p.drug) LIKE '%lixisenatide%'
             OR LOWER(p.drug) LIKE '%albiglutide%'
             OR LOWER(p.drug) LIKE '%victoza%'
             OR LOWER(p.drug) LIKE '%ozempic%'
             OR LOWER(p.drug) LIKE '%byetta%'
             OR LOWER(p.drug) LIKE '%bydureon%'
             OR LOWER(p.drug) LIKE '%trulicity%'
             OR LOWER(p.drug) LIKE '%adlyxin%'
             OR LOWER(p.drug) LIKE '%tanzeum%')
    GROUP BY c.hadm_id
)
SELECT 
    AVG(first_72h) * 100 AS first_72h_rate,
    AVG(last_48h) * 100 AS last_48h_rate,
    (AVG(first_72h) - AVG(last_48h)) * 100 AS absolute_difference
FROM glp1_prescriptions;