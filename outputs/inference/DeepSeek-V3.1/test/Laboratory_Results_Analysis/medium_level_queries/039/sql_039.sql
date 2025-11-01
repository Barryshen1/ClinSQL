WITH chest_pain_admissions AS (
    SELECT DISTINCT a.subject_id, a.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON a.hadm_id = d.hadm_id
    WHERE d.icd_code = 'R07.9'
        AND d.icd_version = 10
),
patient_filtered AS (
    SELECT p.subject_id, p.gender, p.anchor_age
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 87 AND 97
),
first_troponin AS (
    SELECT 
        l.hadm_id,
        MIN(l.charttime) AS first_charttime
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
    WHERE l.itemid = 50963  -- hs-TnT
    GROUP BY l.hadm_id
),
index_troponin AS (
    SELECT 
        l.hadm_id,
        l.valuenum AS value
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
    INNER JOIN first_troponin f
        ON l.hadm_id = f.hadm_id
            AND l.charttime = f.first_charttime
    WHERE l.itemid = 50963
        AND l.valuenum IS NOT NULL
),
categorized AS (
    SELECT 
        it.hadm_id,
        it.value,
        CASE 
            WHEN it.value <= 0.04 THEN 'Normal'
            WHEN it.value <= 0.1 THEN 'Borderline'
            ELSE 'Injury'
        END AS category
    FROM index_troponin it
    INNER JOIN chest_pain_admissions cpa
        ON it.hadm_id = cpa.hadm_id
    INNER JOIN patient_filtered pf
        ON cpa.subject_id = pf.subject_id
)

SELECT 
    category,
    COUNT(*) AS count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage,
    ROUND(AVG(value), 3) AS mean,
    APPROX_QUANTILES(value, 2)[OFFSET(1)] AS median,
    APPROX_QUANTILES(value, 4)[OFFSET(1)] AS q1,
    APPROX_QUANTILES(value, 4)[OFFSET(3)] AS q3
FROM categorized
GROUP BY category
ORDER BY category;