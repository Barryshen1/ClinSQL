WITH chest_pain_admissions AS (
    SELECT 
        a.hadm_id,
        a.edregtime,
        a.admittime,
        a.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON a.hadm_id = d.hadm_id
    WHERE p.gender = 'M'
        AND d.seq_num = 1
        AND (
            (d.icd_version = 9 AND d.icd_code LIKE '786.5%')
            OR (d.icd_version = 10 AND (d.icd_code = 'R07.2' OR d.icd_code = 'R07.9' OR d.icd_code LIKE 'R07.8%'))
        )
        AND CAST(p.anchor_age AS INT64) + (EXTRACT(YEAR FROM a.admittime) - CAST(p.anchor_year AS INT64)) BETWEEN 61 AND 71
),
first_troponin AS (
    SELECT 
        l.hadm_id,
        l.valuenum,
        ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
    INNER JOIN chest_pain_admissions c
        ON l.hadm_id = c.hadm_id
    WHERE l.itemid = 50672
        AND l.valuenum IS NOT NULL
        AND l.valueuom = 'ng/L'
        AND l.charttime >= COALESCE(c.edregtime, c.admittime)
        AND l.charttime <= c.dischtime
),
categorized AS (
    SELECT 
        hadm_id,
        CASE 
            WHEN valuenum < 14 THEN 'normal'
            WHEN valuenum >= 14 AND valuenum < 52 THEN 'borderline'
            WHEN valuenum >= 52 THEN 'myocardial_injury'
        END AS category
    FROM first_troponin
    WHERE rn = 1
)
SELECT 
    category,
    COUNT(*) AS count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage
FROM categorized
GROUP BY category
ORDER BY 
    CASE category 
        WHEN 'normal' THEN 1
        WHEN 'borderline' THEN 2
        WHEN 'myocardial_injury' THEN 3
    END;