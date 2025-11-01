WITH patient_icu AS (
    SELECT 
        p.subject_id,
        p.anchor_age,
        ie.stay_id,
        ie.hadm_id,
        ie.first_careunit,
        ie.intime,
        ie.outtime
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie
        ON p.subject_id = ie.subject_id
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 56 AND 66
),

map_per_stay AS (
    SELECT 
        pi.stay_id,
        AVG(ce.valuenum) AS avg_map
    FROM patient_icu pi
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON pi.stay_id = ce.stay_id
    WHERE ce.itemid = 220181  -- MAP itemid
        AND ce.valuenum IS NOT NULL
    GROUP BY pi.stay_id
),

map_categories AS (
    SELECT 
        stay_id,
        avg_map,
        CASE 
            WHEN avg_map < 65 THEN '<65'
            WHEN avg_map BETWEEN 65 AND 74 THEN '65-74'
            WHEN avg_map BETWEEN 75 AND 84 THEN '75-84'
            WHEN avg_map >= 85 THEN '>=85'
            ELSE 'Other'
        END AS map_category
    FROM map_per_stay
),

stroke_diagnoses AS (
    SELECT 
        hadm_id,
        MAX(CASE 
            WHEN (d.icd_version = 10 AND d.icd_code LIKE 'I63%') 
                OR (d.icd_version = 9 AND (d.icd_code LIKE '433%1' OR d.icd_code LIKE '434%1' OR d.icd_code = '436'))
            THEN 1 
            ELSE 0 
        END) AS has_stroke
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    GROUP BY hadm_id
)

SELECT 
    mc.map_category,
    COUNT(mc.stay_id) AS stay_count,
    SUM(sd.has_stroke) AS stroke_count,
    ROUND(100.0 * SUM(sd.has_stroke) / COUNT(mc.stay_id), 2) AS stroke_rate_percent
FROM map_categories mc
INNER JOIN patient_icu pi
    ON mc.stay_id = pi.stay_id
LEFT JOIN stroke_diagnoses sd
    ON pi.hadm_id = sd.hadm_id
GROUP BY mc.map_category
ORDER BY 
    CASE mc.map_category
        WHEN '<65' THEN 1
        WHEN '65-74' THEN 2
        WHEN '75-84' THEN 3
        WHEN '>=85' THEN 4
        ELSE 5
    END;