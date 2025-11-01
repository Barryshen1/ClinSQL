WITH cohort_admissions AS (
    SELECT
        a.hadm_id,
        a.subject_id,
        a.admittime,
        a.dischtime
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 45 AND 55
        AND a.dischtime IS NOT NULL
    AND EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddx
            ON d.icd_code = ddx.icd_code AND d.icd_version = ddx.icd_version
        WHERE d.hadm_id = a.hadm_id
          AND ddx.long_title LIKE '%Type 2 diabetes mellitus%'
    )
    AND EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddx
            ON d.icd_code = ddx.icd_code AND d.icd_version = ddx.icd_version
        WHERE d.hadm_id = a.hadm_id
          AND ddx.long_title LIKE '%heart failure%'
    )
),
glp1_prescriptions AS (
    SELECT
        c.hadm_id,
        c.subject_id,
        c.admittime,
        c.dischtime,
        p.starttime,
        p.stoptime,
        CASE WHEN p.drug LIKE '%semaglutide%' OR p.drug LIKE '%liraglutide%' OR p.drug LIKE '%exenatide%' 
             OR p.drug LIKE '%dulaglutide%' OR p.drug LIKE '%tirzepatide%' OR p.drug LIKE '%GLP-1%' 
             THEN 1 ELSE 0 END AS is_glp1
    FROM
        cohort_admissions c
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.prescriptions` p
        ON c.hadm_id = p.hadm_id
        AND p.drug IS NOT NULL
),
admission_flags AS (
    SELECT
        hadm_id,
        MAX(CASE WHEN starttime BETWEEN admittime AND DATETIME_ADD(admittime, INTERVAL 72 HOUR) AND is_glp1 = 1 THEN 1 ELSE 0 END) AS started_72h,
        MAX(CASE WHEN starttime <= dischtime 
                 AND (stoptime IS NULL OR stoptime >= DATETIME_SUB(dischtime, INTERVAL 48 HOUR))
                 AND is_glp1 = 1 
                 THEN 1 ELSE 0 END) AS on_48h
    FROM
        glp1_prescriptions
    GROUP BY
        hadm_id
)
SELECT
    (COUNT(CASE WHEN started_72h = 1 THEN 1 END) * 100.0 / COUNT(*)) AS pct_started_72h,
    (COUNT(CASE WHEN on_48h = 1 THEN 1 END) * 100.0 / COUNT(*)) AS pct_on_48h,
    (COUNT(CASE WHEN on_48h = 1 THEN 1 END) - COUNT(CASE WHEN started_72h = 1 THEN 1 END)) * 100.0 / COUNT(*) AS net_change
FROM
    admission_flags;