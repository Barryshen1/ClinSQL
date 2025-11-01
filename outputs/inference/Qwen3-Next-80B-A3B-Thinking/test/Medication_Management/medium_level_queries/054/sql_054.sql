WITH eligible_patients AS (
    SELECT 
        p.subject_id, 
        a.hadm_id, 
        a.admittime, 
        a.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
        ON p.subject_id = a.subject_id
    WHERE 
        p.gender = 'M'
        AND p.anchor_age BETWEEN 56 AND 66
        AND EXISTS (
            SELECT 1 
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
            WHERE d.hadm_id = a.hadm_id
                AND d.icd_code LIKE 'E1%'
        )
        AND EXISTS (
            SELECT 1 
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
            WHERE d.hadm_id = a.hadm_id
                AND d.icd_code LIKE 'I50%'
        )
),
glp1_admins AS (
    SELECT 
        subject_id, 
        hadm_id, 
        charttime
    FROM `physionet-data.mimiciv_3_1_hosp.emar`
    WHERE 
        LOWER(medication) LIKE '%liraglutide%'
        OR LOWER(medication) LIKE '%semaglutide%'
        OR LOWER(medication) LIKE '%exenatide%'
        OR LOWER(medication) LIKE '%dulaglutide%'
        OR LOWER(medication) LIKE '%lixisenatide%'
        OR LOWER(medication) LIKE '%glp-1%'
),
first_48h AS (
    SELECT 
        ep.subject_id, 
        ep.hadm_id,
        COALESCE(MAX(CASE WHEN ga.charttime BETWEEN ep.admittime AND ep.admittime + INTERVAL 48 HOUR THEN 1 ELSE 0 END), 0) AS has_first_48h
    FROM eligible_patients ep
    LEFT JOIN glp1_admins ga 
        ON ep.subject_id = ga.subject_id AND ep.hadm_id = ga.hadm_id
    GROUP BY ep.subject_id, ep.hadm_id
),
final_24h AS (
    SELECT 
        ep.subject_id, 
        ep.hadm_id,
        COALESCE(MAX(CASE WHEN ga.charttime BETWEEN ep.dischtime - INTERVAL 24 HOUR AND ep.dischtime THEN 1 ELSE 0 END), 0) AS has_final_24h
    FROM eligible_patients ep
    LEFT JOIN glp1_admins ga 
        ON ep.subject_id = ga.subject_id AND ep.hadm_id = ga.hadm_id
    GROUP BY ep.subject_id, ep.hadm_id
)
SELECT
    AVG(has_first_48h) * 100 AS first_48h_prevalence,
    AVG(has_final_24h) * 100 AS final_24h_prevalence,
    (AVG(has_final_24h) - AVG(has_first_48h)) * 100 AS net_change
FROM first_48h f
JOIN final_24h g 
    ON f.subject_id = g.subject_id AND f.hadm_id = g.hadm_id;