WITH eligible_patients AS (
    SELECT 
        p.subject_id,
        p.anchor_age,
        i.stay_id,
        i.hadm_id,
        i.intime,
        i.los
    FROM 
        `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN 
        `physionet-data.mimiciv_3_1_icu.icustays` i ON p.subject_id = i.subject_id
    JOIN 
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON i.hadm_id = d.hadm_id
    WHERE 
        p.gender = 'M'
        AND p.anchor_age BETWEEN 84 AND 94
        AND (
            (d.icd_version = 9 AND d.icd_code LIKE '434%')
            OR (d.icd_version = 10 AND d.icd_code LIKE 'I63%')
        )
),
vital_signs AS (
    SELECT 
        e.stay_id,
        COUNT(*) AS abnormal_count
    FROM 
        eligible_patients e
    JOIN 
        `physionet-data.mimiciv_3_1_icu.chartevents` c ON e.stay_id = c.stay_id
    WHERE 
        c.charttime BETWEEN e.intime AND e.intime + INTERVAL 72 HOUR
        AND c.itemid IN (220045, 220050, 220210, 223762)
        AND (
            (c.itemid = 220045 AND (c.valuenum < 60 OR c.valuenum > 100))
            OR (c.itemid = 220050 AND (c.valuenum < 90 OR c.valuenum > 120))
            OR (c.itemid = 220210 AND (c.valuenum < 12 OR c.valuenum > 20))
            OR (c.itemid = 223762 AND (c.valuenum < 36.1 OR c.valuenum > 37.2))
        )
    GROUP BY 
        e.stay_id
),
patient_scores AS (
    SELECT 
        e.stay_id,
        e.hadm_id,
        e.los,
        COALESCE(v.abnormal_count, 0) AS score
    FROM 
        eligible_patients e
    LEFT JOIN 
        vital_signs v ON e.stay_id = v.stay_id
),
percentile_80 AS (
    SELECT 
        (COUNT(CASE WHEN score <= 80 THEN 1 END) * 100.0 / COUNT(*)) AS percentile
    FROM 
        patient_scores
),
top_quartile_threshold AS (
    SELECT 
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY score) AS threshold
    FROM 
        patient_scores
),
mortality_stats AS (
    SELECT 
        AVG(p.los) AS avg_los,
        AVG(CAST(a.hospital_expire_flag AS FLOAT64)) AS mortality_rate
    FROM 
        patient_scores p
    JOIN 
        `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.hadm_id = a.hadm_id
    CROSS JOIN 
        top_quartile_threshold tq
    WHERE 
        p.score >= tq.threshold
)
SELECT 
    p.percentile,
    m.avg_los,
    m.mortality_rate
FROM 
    percentile_80 p
CROSS JOIN 
    mortality_stats m;