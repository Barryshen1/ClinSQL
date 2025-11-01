WITH chest_pain_patients AS (
    SELECT DISTINCT p.subject_id, p.anchor_age, d.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON p.subject_id = d.subject_id
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 84 AND 94
        AND (d.icd_code = 'R07.9' AND d.icd_version = 10
             OR d.icd_code = '786.50' AND d.icd_version = 9)
),
first_troponin AS (
    SELECT 
        cpp.subject_id,
        cpp.hadm_id,
        le.charttime,
        le.valuenum,
        le.flag,
        a.hospital_expire_flag
    FROM chest_pain_patients cpp
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON cpp.subject_id = a.subject_id AND cpp.hadm_id = a.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON cpp.subject_id = le.subject_id AND cpp.hadm_id = le.hadm_id
    WHERE le.itemid = 51003  -- Troponin T
    QUALIFY ROW_NUMBER() OVER (PARTITION BY cpp.hadm_id ORDER BY le.charttime) = 1
),
categorized_troponin AS (
    SELECT
        subject_id,
        hadm_id,
        charttime,
        valuenum,
        hospital_expire_flag,
        CASE 
            WHEN flag = 'Normal' THEN 'normal'
            WHEN flag = 'Borderline' THEN 'borderline'
            WHEN flag IN ('High', 'Abnormal') THEN 'elevated'
            ELSE NULL
        END AS troponin_category
    FROM first_troponin
)
SELECT
    troponin_category,
    COUNT(*) AS count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM categorized_troponin), 2) AS percentage,
    SUM(hospital_expire_flag) AS in_hospital_deaths,
    ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(*), 2) AS mortality_percentage
FROM categorized_troponin
WHERE troponin_category IS NOT NULL
GROUP BY troponin_category
ORDER BY troponin_category;