WITH population AS (
    SELECT 
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.edregtime,
        p.gender,
        p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    INNER JOIN (
        SELECT hadm_id
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
        WHERE seq_num = 1 
            AND icd_version = 10
            AND icd_code IN ('I210','I211','I212','I213','I214','I219','I220','I221','I222','I228','I229')
    ) d
        ON a.hadm_id = d.hadm_id
    WHERE p.gender = 'F'
        AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 64 AND 74
),

first_troponin AS (
    SELECT 
        l.hadm_id,
        l.charttime,
        l.valuenum,
        ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
    INNER JOIN population p
        ON l.hadm_id = p.hadm_id
    WHERE l.itemid = 50341
        AND l.charttime >= COALESCE(p.edregtime, p.admittime)
        AND l.charttime <= p.dischtime
        AND l.valuenum IS NOT NULL
),

troponin_categories AS (
    SELECT 
        p.hadm_id,
        ft.valuenum,
        CASE 
            WHEN ft.valuenum <= 0.014 THEN 'Normal'
            WHEN ft.valuenum BETWEEN 0.015 AND 0.052 THEN 'Borderline'
            WHEN ft.valuenum > 0.052 THEN 'Myocardial Injury'
            ELSE 'Missing'
        END AS category
    FROM population p
    LEFT JOIN first_troponin ft 
        ON p.hadm_id = ft.hadm_id AND ft.rn = 1
)

SELECT
    (COUNTIF(category = 'Normal') * 100.0) / COUNT(*) AS normal_pct,
    (COUNTIF(category = 'Borderline') * 100.0) / COUNT(*) AS borderline_pct,
    (COUNTIF(category = 'Myocardial Injury') * 100.0) / COUNT(*) AS injury_pct
FROM troponin_categories;