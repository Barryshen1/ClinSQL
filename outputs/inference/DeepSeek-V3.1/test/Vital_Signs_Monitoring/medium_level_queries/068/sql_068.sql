WITH cohort AS (
    SELECT 
        p.subject_id, 
        p.anchor_age,
        ie.hadm_id,
        ie.stay_id
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ie.subject_id = p.subject_id
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 41 AND 51
),

map_measurements AS (
    SELECT 
        c.subject_id,
        c.hadm_id,
        c.stay_id,
        ce.charttime,
        ce.valuenum AS map_value,
        CASE 
            WHEN ce.valuenum < 65 THEN '<65'
            WHEN ce.valuenum BETWEEN 65 AND 74 THEN '65-74'
            WHEN ce.valuenum BETWEEN 75 AND 84 THEN '75-84'
            WHEN ce.valuenum >= 85 THEN '>=85'
            ELSE NULL 
        END AS map_category
    FROM cohort c
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON c.subject_id = ce.subject_id
        AND c.hadm_id = ce.hadm_id
        AND c.stay_id = ce.stay_id
    WHERE ce.itemid = 220052  -- MAP itemid
        AND ce.valuenum IS NOT NULL
),

stroke_patients AS (
    SELECT DISTINCT
        c.subject_id,
        c.hadm_id
    FROM cohort c
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON c.subject_id = di.subject_id
        AND c.hadm_id = di.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON di.icd_code = dd.icd_code
        AND di.icd_version = dd.icd_version
    WHERE 
        (dd.icd_version = 10 AND dd.icd_code LIKE 'I63%') OR
        (dd.icd_version = 10 AND dd.icd_code LIKE 'I61%') OR
        (dd.icd_version = 10 AND dd.icd_code LIKE 'I62%') OR
        (dd.icd_version = 10 AND dd.icd_code LIKE 'I64%') OR
        (dd.icd_version = 9 AND dd.icd_code BETWEEN '430' AND '434') OR
        (dd.icd_version = 9 AND dd.icd_code = '436')
),

map_categories AS (
    SELECT 
        map_category,
        COUNT(DISTINCT mm.subject_id) AS total_patients,
        COUNT(DISTINCT CASE WHEN sp.subject_id IS NOT NULL THEN mm.subject_id END) AS stroke_patients
    FROM map_measurements mm
    LEFT JOIN stroke_patients sp
        ON mm.subject_id = sp.subject_id
        AND mm.hadm_id = sp.hadm_id
    WHERE map_category IS NOT NULL
    GROUP BY map_category
)

SELECT 
    map_category,
    total_patients,
    stroke_patients,
    ROUND(100.0 * stroke_patients / total_patients, 2) AS stroke_rate_percent
FROM map_categories
ORDER BY 
    CASE map_category
        WHEN '<65' THEN 1
        WHEN '65-74' THEN 2
        WHEN '75-84' THEN 3
        WHEN '>=85' THEN 4
    END;