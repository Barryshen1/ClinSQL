WITH cohort AS (
    SELECT 
        a.hadm_id,
        a.admittime,
        a.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
    WHERE p.gender = 'F'
      AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 50 AND 60
      AND EXISTS (
          SELECT 1
          FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
          WHERE d.hadm_id = a.hadm_id
            AND (d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E12%' OR d.icd_code LIKE 'E13%' OR d.icd_code LIKE 'E14%')
      )
      AND EXISTS (
          SELECT 1
          FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
          WHERE d.hadm_id = a.hadm_id
            AND d.icd_code LIKE 'I50%'
      )
      AND (a.dischtime - a.admittime) >= INTERVAL '72' HOUR
),
glp1_initiation AS (
    SELECT 
        p.hadm_id,
        MIN(p.starttime) AS first_glp1_time
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    WHERE 
        (LOWER(p.drug) LIKE '%exenatide%' OR 
         LOWER(p.drug) LIKE '%liraglutide%' OR 
         LOWER(p.drug) LIKE '%semaglutide%' OR 
         LOWER(p.drug) LIKE '%dulaglutide%' OR 
         LOWER(p.drug) LIKE '%albiglutide%' OR 
         LOWER(p.drug) LIKE '%byetta%' OR 
         LOWER(p.drug) LIKE '%bydureon%' OR 
         LOWER(p.drug) LIKE '%victoza%' OR 
         LOWER(p.drug) LIKE '%saxenda%' OR 
         LOWER(p.drug) LIKE '%ozempic%' OR 
         LOWER(p.drug) LIKE '%trulicity%' OR 
         LOWER(p.drug) LIKE '%tanzeum%')
        AND LOWER(p.route) LIKE '%subcutaneous%'
    GROUP BY p.hadm_id
),
initiation_periods AS (
    SELECT 
        c.hadm_id,
        CASE
            WHEN g.first_glp1_time BETWEEN c.admittime AND c.admittime + INTERVAL '72' HOUR THEN 'first_72h'
            WHEN g.first_glp1_time BETWEEN c.dischtime - INTERVAL '72' HOUR AND c.dischtime THEN 'last_72h'
            ELSE 'neither'
        END AS period
    FROM cohort c
    LEFT JOIN glp1_initiation g ON c.hadm_id = g.hadm_id
)
SELECT 
    SUM(CASE WHEN period = 'first_72h' THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS first_72h_rate,
    SUM(CASE WHEN period = 'last_72h' THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS last_72h_rate,
    (SUM(CASE WHEN period = 'last_72h' THEN 1 ELSE 0 END) * 1.0 / COUNT(*)) - 
    (SUM(CASE WHEN period = 'first_72h' THEN 1 ELSE 0 END) * 1.0 / COUNT(*)) AS absolute_change,
    ((SUM(CASE WHEN period = 'last_72h' THEN 1 ELSE 0 END) * 1.0 / COUNT(*)) - 
    (SUM(CASE WHEN period = 'first_72h' THEN 1 ELSE 0 END) * 1.0 / COUNT(*))) / 
    NULLIF(SUM(CASE WHEN period = 'first_72h' THEN 1 ELSE 0 END) * 1.0 / COUNT(*), 0) AS relative_change
FROM initiation_periods;