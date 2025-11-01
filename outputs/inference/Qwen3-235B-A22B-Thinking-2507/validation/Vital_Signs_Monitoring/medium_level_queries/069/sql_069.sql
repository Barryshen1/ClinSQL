WITH eligible_stays AS (
    SELECT 
        i.stay_id,
        i.hadm_id,
        i.intime,
        p.subject_id,
        p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year) AS age
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON i.subject_id = p.subject_id
    WHERE p.gender = 'F'
        AND (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) BETWEEN 41 AND 51
),
rr_measurements AS (
    SELECT 
        c.stay_id,
        c.valuenum
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
    INNER JOIN eligible_stays e
        ON c.stay_id = e.stay_id
    WHERE c.itemid = 220210
        AND c.valuenum IS NOT NULL
        AND c.charttime >= e.intime
        AND c.charttime <= DATETIME_ADD(e.intime, INTERVAL 48 HOUR)
),
stay_rr AS (
    SELECT 
        stay_id,
        AVG(valuenum) AS avg_rr
    FROM rr_measurements
    GROUP BY stay_id
),
stroke_flag AS (
    SELECT 
        e.hadm_id,
        COALESCE(MAX(CASE 
            WHEN d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR 
                 d.icd_code LIKE 'I63%' OR d.icd_code LIKE 'I64%' 
            THEN 1 ELSE 0 
        END), 0) AS stroke_flag
    FROM eligible_stays e
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON e.hadm_id = d.hadm_id
    GROUP BY e.hadm_id
)
SELECT 
    CASE 
        WHEN avg_rr < 12 THEN '<12'
        WHEN avg_rr BETWEEN 12 AND 20 THEN '12-20'
        WHEN avg_rr BETWEEN 21 AND 29 THEN '21-29'
        WHEN avg_rr >= 30 THEN '>=30'
        ELSE NULL 
    END AS rr_category,
    COUNT(*) AS count_stays,
    AVG(stroke_flag) AS stroke_rate
FROM stay_rr s
INNER JOIN eligible_stays e ON s.stay_id = e.stay_id
INNER JOIN stroke_flag sf ON e.hadm_id = sf.hadm_id
GROUP BY rr_category
ORDER BY 
    CASE rr_category
        WHEN '<12' THEN 1
        WHEN '12-20' THEN 2
        WHEN '21-29' THEN 3
        WHEN '>=30' THEN 4
    END;