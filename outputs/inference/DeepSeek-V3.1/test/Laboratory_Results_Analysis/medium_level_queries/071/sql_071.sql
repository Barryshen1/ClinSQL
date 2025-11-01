WITH cohort AS (
    SELECT 
        p.subject_id, 
        p.anchor_age,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_hospital
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 43 AND 53
),

first_troponin AS (
    SELECT 
        l.hadm_id,
        l.charttime,
        l.itemid,
        l.value,
        l.valuenum,
        l.flag,
        d.label,
        ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
    INNER JOIN cohort c
        ON l.hadm_id = c.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d
        ON l.itemid = d.itemid
    WHERE d.label LIKE '%troponin t%'
        AND l.charttime IS NOT NULL
),

categorized_troponin AS (
    SELECT 
        hadm_id,
        charttime,
        CASE 
            WHEN itemid = 51003 THEN -- qualitative
                CASE 
                    WHEN UPPER(value) LIKE '%NEGATIVE%' THEN 'Normal'
                    WHEN UPPER(value) LIKE '%BORDERLINE%' THEN 'Borderline'
                    WHEN UPPER(value) LIKE '%POSITIVE%' THEN 'Elevated'
                    ELSE NULL
                END
            WHEN itemid = 51002 THEN -- quantitative
                CASE 
                    WHEN flag = 'Normal' THEN 'Normal'
                    WHEN flag = 'High' THEN 'Elevated'
                    ELSE NULL
                END
            ELSE NULL
        END AS troponin_category
    FROM first_troponin
    WHERE rn = 1
)

SELECT 
    troponin_category,
    COUNT(*) AS admission_count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM categorized_troponin), 2) AS percentage,
    ROUND(AVG(c.los_hospital), 2) AS avg_los_days
FROM categorized_troponin ct
INNER JOIN cohort c
    ON ct.hadm_id = c.hadm_id
WHERE troponin_category IS NOT NULL
GROUP BY troponin_category
ORDER BY troponin_category;