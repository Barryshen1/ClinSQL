WITH 
admissions_with_ami AS (
    SELECT 
        a.hadm_id,
        a.subject_id,
        a.admittime,
        p.gender,
        EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
        ON a.hadm_id = d.hadm_id
    WHERE 
        p.gender = 'F'
        AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 40 AND 50
        AND (d.icd_code LIKE '410.%' OR d.icd_code LIKE 'I21.%')
    GROUP BY a.hadm_id, a.subject_id, a.admittime, p.gender, age_at_admission
),

first_troponin_t AS (
    SELECT 
        l.hadm_id,
        l.valuenum,
        ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime ASC) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
    WHERE 
        l.itemid IN (
            SELECT itemid 
            FROM `physionet-data.mimiciv_3_1_hosp.d_labitems` 
            WHERE label LIKE '%Troponin T%' AND category LIKE '%Cardiac%'
        )
),

troponin_categorized AS (
    SELECT 
        a.hadm_id,
        f.valuenum,
        CASE 
            WHEN f.valuenum < 0.01 THEN 'normal'
            WHEN f.valuenum >= 0.01 AND f.valuenum < 0.1 THEN 'borderline'
            WHEN f.valuenum >= 0.1 THEN 'elevated'
            ELSE 'unknown' 
        END AS troponin_category
    FROM admissions_with_ami a
    INNER JOIN first_troponin_t f 
        ON a.hadm_id = f.hadm_id
    WHERE f.rn = 1
)

SELECT 
    troponin_category,
    COUNT(*) AS count
FROM troponin_categorized
GROUP BY troponin_category
ORDER BY troponin_category;